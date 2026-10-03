"""Reference pipeline for counting colony-forming units on agar plate photos.

The mobile app must reproduce the results of this package on the golden test set.
"""

from .pipeline import CountResult, count_colonies
from .plate import Plate, find_plate

__all__ = ["CountResult", "Plate", "count_colonies", "find_plate"]
__version__ = "0.1.0"
