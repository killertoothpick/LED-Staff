from __future__ import annotations

import math
from collections.abc import Callable

import config
from core.context import IMUState


class IMUReader:
    """Read IMU values using the project axis convention.

    Confirmed physical convention:
      x = right
      y = up
      z = perpendicular / the remaining axis
    """

    def __init__(self, logger: Callable[[str], None] | None = None) -> None:
        self._logger = logger or print
        self.sensor = None
        self.available = False
        self.last = IMUState()
        if not config.MOCK_HARDWARE:
            self._init_sensor()

    def _init_sensor(self) -> None:
        try:
            import board
            from adafruit_lsm6ds.lsm6dsox import LSM6DSOX

            i2c = board.I2C()
            self.sensor = LSM6DSOX(i2c)
            self.available = True
            self._logger("IMU initialized; axes: x=right y=up z=perpendicular")
        except Exception as exc:
            self.sensor = None
            self.available = False
            self._logger(f"IMU unavailable, continuing without it: {exc}")

    def update(self) -> IMUState:
        if not self.available or self.sensor is None:
            self.last = IMUState(available=False)
            return self.last
        try:
            # Raw sensor axes, interpreted as x=right, y=up, z=perpendicular.
            ax, ay, az = self.sensor.acceleration
            motion = math.sqrt(ax * ax + ay * ay + az * az)
            tilt_x = math.atan2(ax, math.sqrt(ay * ay + az * az))
            tilt_y = math.atan2(ay, math.sqrt(ax * ax + az * az))
            tilt_angle = math.atan2(ay, ax)
            gx = gy = gz = 0.0
            try:
                gx, gy, gz = self.sensor.gyro
            except Exception:
                pass
            self.last = IMUState(
                ax=ax,
                ay=ay,
                az=az,
                gx=gx,
                gy=gy,
                gz=gz,
                motion=motion,
                tilt_x=tilt_x,
                tilt_y=tilt_y,
                tilt_angle=tilt_angle,
                available=True,
            )
        except Exception as exc:
            self._logger(f"IMU read failed: {exc}")
            self.available = False
            self.last = IMUState(available=False)
        return self.last

    def snapshot(self) -> IMUState:
        return self.last
