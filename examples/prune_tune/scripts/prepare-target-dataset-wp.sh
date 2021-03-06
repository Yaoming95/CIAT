# Copyright 2020 ByteDance Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#!/usr/bin/env bash
set -e

THIS_DIR="$( cd "$( dirname "$0" )" && pwd )"

pip3 install -e $THIS_DIR/../../../ --no-deps

DATA_PATH=$1
# mkdir -p ${DATA_PATH}
DATA_PATH="$( cd "$DATA_PATH" && pwd )"

# download data and learn word piece vocabulary
# python3 $THIS_DIR/download_wmt14en2de.py --output_dir $DATA_PATH --learn_wordpiece

TRAIN_SRC=$DATA_PATH/train.en
TRAIN_TRG=$DATA_PATH/train.de
DEV_SRC=$DATA_PATH/dev.en
DEV_TRG=$DATA_PATH/dev.de
TEST_SRC=$DATA_PATH/test.en
TEST_TRG=$DATA_PATH/test.de


echo "shuffling..."
get_seeded_random()
{
  seed="$1"
  openssl enc -aes-256-ctr -pass pass:"$seed" -nosalt \
    </dev/zero 2>/dev/null
}

random_source=`date +%N`
shuf --random-source=<(get_seeded_random $random_source) \
    $TRAIN_SRC > $DATA_PATH/train.en.shuf
shuf --random-source=<(get_seeded_random $random_source) \
    $TRAIN_TRG > $DATA_PATH/train.de.shuf

mv $DATA_PATH/train.en.shuf $TRAIN_SRC
mv $DATA_PATH/train.de.shuf $TRAIN_TRG

RECORDS_PATH=$DATA_PATH/train_records

# pre-process training data and generate tf-records
mkdir -p $RECORDS_PATH
rm -f FAILED

PROCESSORS_IN_PARALLEL=8
NUM_PROCESSORS=8
TOTAL_SHARDS=32
SHARD_PER_PROCESS=$((TOTAL_SHARDS / NUM_PROCESSORS))
LOOP=$((NUM_PROCESSORS / PROCESSORS_IN_PARALLEL))

for loopid in $(seq 1 ${LOOP}); do
    start=$(($((loopid - 1)) * ${PROCESSORS_IN_PARALLEL}))
    end=$(($start + PROCESSORS_IN_PARALLEL - 1))
    echo $start, $end
    for procid in $(seq $start $end); do
        set -x
        nice -n 10 python3 -m neurst.cli.create_tfrecords \
            --processor_id $procid --num_processors $NUM_PROCESSORS \
            --num_output_shards $TOTAL_SHARDS \
            --output_range_begin "$((SHARD_PER_PROCESS * procid))" \
            --output_range_end "$((SHARD_PER_PROCESS * procid + SHARD_PER_PROCESS))" \
        --dataset ParallelTextDataset \
        --src_file $TRAIN_SRC --trg_file $TRAIN_TRG \
        --task.class translation \
        --task.params "\
            src_data_pipeline.class: TextDataPipeline
            src_data_pipeline.params:
              language: en
              subtokenizer: wordpiece
              subtokenizer_codes: http://lf3-nlp-opensource.bytetos.com/obj/nlp-opensource/neurst/prune_tune/vocab
              vocab_path: http://lf3-nlp-opensource.bytetos.com/obj/nlp-opensource/neurst/prune_tune/vocab
            trg_data_pipeline.class: TextDataPipeline
            trg_data_pipeline.params:
              language: de
              subtokenizer: wordpiece
              subtokenizer_codes: http://lf3-nlp-opensource.bytetos.com/obj/nlp-opensource/neurst/prune_tune/vocab
              vocab_path: http://lf3-nlp-opensource.bytetos.com/obj/nlp-opensource/neurst/prune_tune/vocab" \
        --output_template $RECORDS_PATH/train.tfrecords-%5.5d-of-%5.5d || touch FAILED &
        set +x
    done
    wait
    ! [[ -f FAILED ]]
done

# cp $THIS_DIR/training_args.yml $DATA_PATH/training_args.yml

cat $THIS_DIR/validation_args.yml | \
    sed "s#STR_EVL#0#" | \
    sed "s#EVL_STEP#400#" | \
    sed "s#DEV_SRC#$DATA_PATH/dev.en#" | \
    sed "s#DEV_TRG#$DATA_PATH/dev.de#" > $DATA_PATH/validation_args.yml

cat $THIS_DIR/prediction_args.yml | \
    sed "s#DEV_SRC#$DATA_PATH/dev.en#" | \
    sed "s#DEV_TRG#$DATA_PATH/dev.de#" | \
    sed "s#TEST_SRC#$DATA_PATH/test.en#" | \
    sed "s#TEST_TRG#$DATA_PATH/test.de#" > $DATA_PATH/prediction_args.yml

echo "
dataset.class: ParallelTFRecordDataset
dataset.params:
  data_path: $RECORDS_PATH

task.class: translation
task.params:
  batch_by_tokens: True
  batch_size: 32768
  max_src_len: 128
  max_trg_len: 128
  src_data_pipeline.class: TextDataPipeline
  src_data_pipeline.params:
    language: en
    subtokenizer: wordpiece
    subtokenizer_codes: http://lf3-nlp-opensource.bytetos.com/obj/nlp-opensource/neurst/prune_tune/vocab
    vocab_path: http://lf3-nlp-opensource.bytetos.com/obj/nlp-opensource/neurst/prune_tune/vocab
  trg_data_pipeline.class: TextDataPipeline
  trg_data_pipeline.params:
    language: de
    subtokenizer: wordpiece
    subtokenizer_codes: http://lf3-nlp-opensource.bytetos.com/obj/nlp-opensource/neurst/prune_tune/vocab
    vocab_path: http://lf3-nlp-opensource.bytetos.com/obj/nlp-opensource/neurst/prune_tune/vocab
" > $DATA_PATH/translation_wordpiece.yml

echo "
entry.class: trainer
entry.params:
  train_steps: 10000
  summary_steps: 200
  save_checkpoint_steps: 1000
  criterion.class: label_smoothed_cross_entropy
  criterion.params:
    label_smoothing: 0.1
" > $DATA_PATH/training_args.yml
