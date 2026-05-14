from __future__ import annotations

import signal
import time
from pathlib import Path

import config
from animations import build_animations
from core.context import FrameContext
from core.debug import DebugDashboard, RuntimeLog, menu_value_text
from core.memory import MemoryMaintenance
from core.presets import PresetStore
from core.timing import FPSCounter
from hardware.audio import AudioProcessor
from hardware.beat import BeatTracker
from hardware.buttons import ButtonScanner
from hardware.imu import IMUReader
from hardware.leds import StaffSurface, boot_animation
from ui.menu import UIState
from ui.pages import build_pages


running = True

# Physical UI convention:
# - In settings: TL/TR change page; BL/BR change current setting value.
# - In run mode: TL/TR save current preset and load previous/next preset.
# - In run mode: BL/BR are animation hotkeys and save the current preset.
PAGE_PREV = -1
PAGE_NEXT = 1
VALUE_DOWN = -1
VALUE_UP = 1
ANIM_PREV = -1
ANIM_NEXT = 1
PRESET_PREV = -1
PRESET_NEXT = 1


def handle_signal(signum, frame):
    global running
    running = False


def resolve_path(relative: str) -> Path:
    return Path(__file__).resolve().parent / relative


def animation_name(animations, settings) -> str:
    if not animations:
        return "none"
    return animations[settings.animation_index % len(animations)].name


def save_slot(log: RuntimeLog, presets: PresetStore, slot: int, settings, *, reason: str) -> None:
    try:
        presets.save_current(slot, settings, remember=True)
        log.add(f"Saved preset slot {slot + 1}: {reason}")
    except Exception as exc:
        log.add(f"Preset save failed for slot {slot + 1}: {exc}")


def main() -> int:
    global running
    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)

    log = RuntimeLog()
    dashboard = DebugDashboard()
    memory = MemoryMaintenance(logger=log.add)
    log.add("LED staff runtime starting")

    staff = StaffSurface.create()
    staff.clear()
    staff.show()
    boot_animation(staff)

    buttons = ButtonScanner()
    imu = IMUReader(logger=log.add)
    audio = AudioProcessor(logger=log.add)
    beat = BeatTracker()
    audio.start()

    animations = build_animations()
    pages = build_pages()
    presets = PresetStore.load(resolve_path(config.PRESET_PATH), animation_count=len(animations))

    active_settings = presets.get(presets.last_active_slot)
    active_settings.clamp(animation_count=len(animations))
    pending_settings = active_settings.copy()
    ui = UIState(preset_slot=presets.last_active_slot)

    log.add(f"Loaded preset slot {presets.last_active_slot + 1}")
    log.add(f"Preset model: {config.PRESET_SLOTS} slots; last {getattr(config, 'RANDOM_VISUAL_PRESET_COUNT', 0)} start with random visuals at boot")
    log.add(f"Top geometry: {config.TOP_COUNT} logical mirrored LEDs; first {config.TOP_TRIANGLE_SHARED_COUNT} shared, remaining {config.TOP_TRIANGLE_BRANCH_COUNT} branch")

    fps = FPSCounter(config.FPS_LOG_INTERVAL)
    frame = 0
    last = time.monotonic()

    try:
        while running:
            frame_start = time.monotonic()
            dt = max(0.0001, min(0.1, frame_start - last))
            last = frame_start

            button_events = buttons.update(frame_start)

            imu_state = imu.update()
            audio_state = audio.snapshot(gain=active_settings.gain)
            beat_state = beat.update(frame_start, audio_state)

            if not ui.in_settings:
                if button_events["BC"].tap:
                    pending_settings = ui.enter_settings(frame_start, active_settings)
                    page = pages[ui.page_index]
                    log.add(f"Entered settings: {page.name} = {menu_value_text(page.name, pending_settings, ui, animations, pages, presets)}")

                # Run-mode preset cycling: save the slot we are leaving, then load the neighboring slot.
                if button_events["TL"].tap or button_events["TR"].tap:
                    old_slot = ui.preset_slot % config.PRESET_SLOTS
                    direction = PRESET_NEXT if button_events["TR"].tap else PRESET_PREV
                    save_slot(log, presets, old_slot, active_settings, reason="leaving slot")

                    ui.preset_slot = (old_slot + direction) % config.PRESET_SLOTS
                    presets.last_active_slot = ui.preset_slot
                    active_settings = presets.get(ui.preset_slot)
                    active_settings.clamp(animation_count=len(animations))
                    pending_settings = active_settings.copy()
                    try:
                        presets.remember_active_slot(ui.preset_slot)
                    except Exception as exc:
                        log.add(f"Preset active-slot save failed: {exc}")
                    log.add(f"Loaded preset slot {ui.preset_slot + 1}: anim={animation_name(animations, active_settings)} palette={active_settings.palette.name} speed={active_settings.speed.name} brightness={active_settings.brightness:.2f} gain={active_settings.gain:.2f}")

                # Run-mode animation hotkeys: BL previous animation, BR next animation; persist current slot.
                if button_events["BL"].tap or button_events["BR"].tap:
                    direction = ANIM_NEXT if button_events["BR"].tap else ANIM_PREV
                    active_settings.animation_index = (active_settings.animation_index + direction) % max(1, len(animations))
                    pending_settings = active_settings.copy()
                    save_slot(log, presets, ui.preset_slot, active_settings, reason="animation hotkey")
                    log.add(f"Animation hotkey: {animation_name(animations, active_settings)}")
            else:
                if button_events["BC"].hold:
                    pending_settings = active_settings.copy()
                    log.add("Canceled settings with BC hold")
                    ui.exit_settings()
                elif button_events["BC"].tap:
                    page = pages[ui.page_index]
                    value_before_apply = menu_value_text(page.name, pending_settings, ui, animations, pages, presets)
                    replacement = page.on_apply(pending_settings, ui, presets, frame_start)
                    if replacement is not None:
                        pending_settings = replacement
                        pending_settings.clamp(animation_count=len(animations))
                    active_settings = pending_settings.copy()
                    active_settings.clamp(animation_count=len(animations))
                    save_slot(log, presets, ui.preset_slot, active_settings, reason=f"applied {page.name}")
                    log.add(f"Applied settings from {page.name}: {value_before_apply}")
                    ui.exit_settings()
                else:
                    # Settings page navigation: TL previous page, TR next page.
                    if button_events["TL"].tap:
                        ui.set_page(ui.page_index + PAGE_PREV, len(pages), frame_start)
                        page = pages[ui.page_index]
                        log.add(f"Menu page previous: {page.name} = {menu_value_text(page.name, pending_settings, ui, animations, pages, presets)}")
                    if button_events["TR"].tap:
                        ui.set_page(ui.page_index + PAGE_NEXT, len(pages), frame_start)
                        page = pages[ui.page_index]
                        log.add(f"Menu page next: {page.name} = {menu_value_text(page.name, pending_settings, ui, animations, pages, presets)}")

                    # Settings value changes: BL down/counter-clockwise, BR up/clockwise.
                    if button_events["BL"].tap:
                        page = pages[ui.page_index]
                        page.adjust(pending_settings, VALUE_DOWN, ui, len(animations), presets)
                        pending_settings.clamp(animation_count=len(animations))
                        ui.touch(frame_start)
                        log.add(f"{page.name} value down: {menu_value_text(page.name, pending_settings, ui, animations, pages, presets)}")
                    if button_events["BR"].tap:
                        page = pages[ui.page_index]
                        page.adjust(pending_settings, VALUE_UP, ui, len(animations), presets)
                        pending_settings.clamp(animation_count=len(animations))
                        ui.touch(frame_start)
                        log.add(f"{page.name} value up: {menu_value_text(page.name, pending_settings, ui, animations, pages, presets)}")

                    if ui.timed_out(frame_start):
                        pending_settings = active_settings.copy()
                        log.add("Settings timed out; pending changes canceled")
                        ui.exit_settings()

            staff.clear()
            staff.set_output_scale(active_settings.brightness)
            ctx = FrameContext(
                now=frame_start,
                dt=dt,
                frame=frame,
                settings=active_settings,
                beat=beat_state,
                imu=imu_state,
                audio=audio_state,
            )
            animation = animations[active_settings.animation_index % len(animations)]
            if beat_state.just_beat:
                animation.on_beat(ctx)
            animation.render_staff(staff, ctx)

            if ui.in_settings:
                pending_audio = audio.snapshot(gain=pending_settings.gain)
                circle_ctx = FrameContext(
                    now=frame_start,
                    dt=dt,
                    frame=frame,
                    settings=pending_settings,
                    beat=beat_state,
                    imu=imu_state,
                    audio=pending_audio,
                )
                pages[ui.page_index].render_circle(staff, circle_ctx, ui, animations)

            staff.show()

            report = fps.tick(frame_start)
            if report is not None and not dashboard.enabled:
                log.add(
                    f"fps={report:.1f} mode={'settings' if ui.in_settings else 'run'} "
                    f"preset={ui.preset_slot + 1} anim={animation.name} palette={active_settings.palette.name} "
                    f"speed={active_settings.speed.name} bpm={beat_state.bpm_smooth:.1f}"
                )

            dashboard.render(
                now=frame_start,
                frame=frame,
                fps_report=report,
                ui=ui,
                pages=pages,
                animations=animations,
                active_settings=active_settings,
                pending_settings=pending_settings,
                imu_state=imu_state,
                audio_state=audio_state,
                beat_state=beat_state,
                log=log,
                presets=presets,
            )

            memory.tick(frame_start)

            frame += 1
            elapsed = time.monotonic() - frame_start
            sleep_time = config.FRAME_TIME - elapsed
            if sleep_time > 0:
                time.sleep(sleep_time)
    finally:
        log.add("LED staff runtime stopping")
        audio.stop()
        staff.clear()
        staff.show()
        try:
            buttons.cleanup()
        except Exception:
            pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
