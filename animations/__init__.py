from animations.accel_rgb import AccelRGB
from animations.charge import Charge
from animations.running_dot import RunningDot
from animations.sparkle import Sparkle
from animations.spiral import TiltSpiral
from animations.level_stripes import LevelStripes


def build_animations():
    return [
        AccelRGB(),
        Charge(),
        Sparkle(),
        RunningDot(),
        TiltSpiral(),
        LevelStripes(),
    ]
