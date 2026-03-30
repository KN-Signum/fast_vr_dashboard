import asyncio
import random
from dataclasses import dataclass, asdict


# --- Data models ---

@dataclass
class Vector3:
    x: float
    y: float
    z: float


@dataclass
class EyeTransform:
    """3D rotation matrix as 3 orthonormal axes + origin (eye world position)."""
    x_axis: Vector3  # Right vector
    y_axis: Vector3  # Up vector
    z_axis: Vector3  # Forward / gaze direction
    origin: Vector3  # Eye position in world space


@dataclass
class EyeTrackingData:
    type: str = "eye_tracking"
    player_position: Vector3 = None
    eyes_position: Vector3 = None
    eyes_transform: EyeTransform = None

    def to_dict(self) -> dict:
        """Convert to JSON-serializable dict matching the agreed protocol schema."""
        return {
            "type": self.type,
            "player_position": asdict(self.player_position),
            "eyes_position": asdict(self.eyes_position),
            "eyes_transform": {
                "x_axis": asdict(self.eyes_transform.x_axis),
                "y_axis": asdict(self.eyes_transform.y_axis),
                "z_axis": asdict(self.eyes_transform.z_axis),
                "origin": asdict(self.eyes_transform.origin),
            },
        }


# --- Mock stream ---

# Set to False to stop the mock task gracefully
et_stream_enabled = True


async def eye_tracking_mock_task(manager) -> None:
    """
    Mock ET stream: broadcasts realistic single-eye data at ~20 FPS.

    Useful for local development without a connected VR headset.
    In production, disable this and let the VR game send real ET events
    with `"type": "eye_tracking"` over the shared WebSocket.
    """
    global et_stream_enabled
    print("👁️ Eye-tracking mock stream started (20 FPS)...")

    base_player_pos = Vector3(x=120.0, y=3.0, z=95.0)
    base_eyes_pos = Vector3(x=120.0, y=3.65, z=95.0)

    try:
        while et_stream_enabled:
            eyes_x = base_eyes_pos.x + random.uniform(-0.5, 0.5)
            eyes_y = base_eyes_pos.y + random.uniform(-0.3, 0.3)
            eyes_z = base_eyes_pos.z + random.uniform(-0.5, 0.5)

            x_axis = Vector3(x=0.97 + random.uniform(-0.02, 0.02), y=-0.018, z=-0.244)
            y_axis = Vector3(x=0.014, y=0.9998 + random.uniform(-0.02, 0.02), z=-0.015)
            z_axis = Vector3(x=0.244, y=0.011, z=0.970 + random.uniform(-0.02, 0.02))

            et_data = EyeTrackingData(
                player_position=base_player_pos,
                eyes_position=Vector3(x=eyes_x, y=eyes_y, z=eyes_z),
                eyes_transform=EyeTransform(
                    x_axis=x_axis,
                    y_axis=y_axis,
                    z_axis=z_axis,
                    origin=Vector3(x=eyes_x, y=eyes_y, z=eyes_z),
                ),
            )

            await manager.broadcast_json(et_data.to_dict())
            await asyncio.sleep(0.05)

    except asyncio.CancelledError:
        print("👁️ Eye-tracking mock stream stopped")
    except Exception as e:
        print(f"❌ Eye-tracking mock error: {e}")
