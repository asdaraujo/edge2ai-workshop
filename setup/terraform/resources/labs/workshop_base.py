#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Common utilities for Python scripts
"""
from . import *


class BaseWorkshop(AbstractWorkshop):

    @classmethod
    def workshop_id(cls):
        """Return a short string to identify the workshop."""
        return 'base'

    @classmethod
    def prereqs(cls):
        """
        Return a list of prereqs for this workshop. The list can contain either:
          - Strings identifying the name of other workshops that need to be setup before this one does. In
            this case all the labs of the specified workshop will be setup.
          - Tuples (String, Integer), where the String specifies the name of the workshop and Integer the number
            of the last lab of that workshop to be executed/setup.
        """
        return ['nifi']

    def before_setup(self):
        pass

    def after_setup(self):
        pass

    def teardown(self):
        pass
