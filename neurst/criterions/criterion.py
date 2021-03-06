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
from abc import ABCMeta, abstractmethod

import six


@six.add_metaclass(ABCMeta)
class Criterion(object):
    REGISTRY_NAME = "criterion"

    def __init__(self):
        self._model = None

    @staticmethod
    def class_or_method_args():
        """ Returns a list of args for flag definition. """
        return []

    @abstractmethod
    def __call__(self, model_inp, model_out):
        """ Calculates according to model inputs and model outputs.

        Returns a list of tensors.
        """
        raise NotImplementedError

    @abstractmethod
    def reduce_loss(self, model_inp, model_out):
        """ Reduces loss tensor for training according to the model inputs
            and outputs.

        Returns: A float tensor.
        """
        raise NotImplementedError

    @abstractmethod
    def reduce_metrics(self, eval_res_list):
        """ Reduces the metrics according to a list of returned value from `eval`.

        Args:
            eval_res_list: A list of tuples of numpy.ndarray generated by `self.__call__`
                and model.__call__.

        Returns:
            A dict of reduced metrics for evaluation.
        """
        raise NotImplementedError

    def reduce_sample_metrics(self, eval_res):
        """ Reduces the metrics at sample level.

        Args:
            eval_res: A tuple of numpy.ndarray or tensors generated by `self.__call__`.

        Returns:
            A list of dict of reduced metrics for evaluation.
        """
        raise NotImplementedError

    @abstractmethod
    def as_metric(self):
        """ Returns a wrapper class of Metric. """
        raise NotImplementedError

    def set_model(self, model):
        self._model = model

    @property
    def model(self):
        return self._model
