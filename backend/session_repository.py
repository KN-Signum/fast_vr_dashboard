from __future__ import annotations

import json
import shutil
import sqlite3
import tempfile
import uuid
import zipfile
from contextlib import contextmanager
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Iterable, Iterator


STREAM_FILES = {
    "eeg_records": "eeg.ndjson",
    "eye_tracking_records": "eye_tracking.ndjson",
    "vr_events": "vr_events.ndjson",
    "vr_frames": "vr_frames.ndjson",
}
COUNT_COLUMNS = (*STREAM_FILES.keys(),)


class SessionRepositoryError(RuntimeError):
    pass


class ActiveSessionExistsError(SessionRepositoryError):
    pass


class SessionNotFoundError(SessionRepositoryError):
    pass


class SessionStateError(SessionRepositoryError):
    pass


def utc_now() -> datetime:
    return datetime.now(UTC)


def isoformat(value: datetime) -> str:
    return value.astimezone(UTC).isoformat().replace("+00:00", "Z")


def parse_timestamp(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


class SessionRepository:
    def __init__(self, database_path: Path, session_root: Path) -> None:
        self.database_path = database_path
        self.session_root = session_root

    def initialize(self) -> None:
        self.database_path.parent.mkdir(parents=True, exist_ok=True)
        self.session_root.mkdir(parents=True, exist_ok=True)
        with self._connect() as connection:
            connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS sessions (
                    id TEXT PRIMARY KEY,
                    patient_id TEXT NOT NULL,
                    preferred_hand TEXT NOT NULL,
                    notes TEXT NOT NULL,
                    post_session_notes TEXT NOT NULL DEFAULT '',
                    eeg_enabled_at_start INTEGER NOT NULL DEFAULT 1,
                    status TEXT NOT NULL,
                    started_at TEXT NOT NULL,
                    ended_at TEXT,
                    duration_ms INTEGER,
                    eeg_records INTEGER NOT NULL DEFAULT 0,
                    eye_tracking_records INTEGER NOT NULL DEFAULT 0,
                    vr_events INTEGER NOT NULL DEFAULT 0,
                    vr_frames INTEGER NOT NULL DEFAULT 0,
                    session_events INTEGER NOT NULL DEFAULT 0,
                    dropped_records INTEGER NOT NULL DEFAULT 0,
                    recovery_pending INTEGER NOT NULL DEFAULT 0,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );

                CREATE UNIQUE INDEX IF NOT EXISTS one_active_session
                    ON sessions(status)
                    WHERE status = 'active';

                CREATE TABLE IF NOT EXISTS session_events (
                    id TEXT PRIMARY KEY,
                    session_id TEXT NOT NULL,
                    label TEXT NOT NULL,
                    category TEXT NOT NULL,
                    note TEXT NOT NULL,
                    occurred_at TEXT NOT NULL,
                    elapsed_ms INTEGER NOT NULL,
                    source TEXT NOT NULL,
                    FOREIGN KEY(session_id) REFERENCES sessions(id)
                );

                CREATE INDEX IF NOT EXISTS session_events_by_session
                    ON session_events(session_id, elapsed_ms);
                """
            )
            columns = {
                row["name"]
                for row in connection.execute("PRAGMA table_info(sessions)").fetchall()
            }
            if "recovery_pending" not in columns:
                connection.execute(
                    """
                    ALTER TABLE sessions
                    ADD COLUMN recovery_pending INTEGER NOT NULL DEFAULT 0
                    """
                )
            if "eeg_enabled_at_start" not in columns:
                connection.execute(
                    """
                    ALTER TABLE sessions
                    ADD COLUMN eeg_enabled_at_start INTEGER NOT NULL DEFAULT 1
                    """
                )
            if "post_session_notes" not in columns:
                connection.execute(
                    """
                    ALTER TABLE sessions
                    ADD COLUMN post_session_notes TEXT NOT NULL DEFAULT ''
                    """
                )

    def create_session(
        self,
        *,
        patient_id: str,
        preferred_hand: str,
        notes: str,
        eeg_enabled_at_start: bool = True,
    ) -> dict[str, Any]:
        now = utc_now()
        session_id = str(uuid.uuid4())
        timestamp = isoformat(now)
        directory = self.session_directory(session_id)
        directory.mkdir(parents=True, exist_ok=False)
        for filename in (*STREAM_FILES.values(), "session_events.ndjson"):
            (directory / filename).touch()
        try:
            with self._connect() as connection:
                connection.execute("BEGIN IMMEDIATE")
                active = connection.execute(
                    "SELECT id FROM sessions WHERE status = 'active'"
                ).fetchone()
                if active is not None:
                    raise ActiveSessionExistsError(
                        f"Sesja {active['id']} jest już aktywna"
                    )
                connection.execute(
                    """
                    INSERT INTO sessions (
                        id, patient_id, preferred_hand, notes,
                        eeg_enabled_at_start, status,
                        started_at, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, 'active', ?, ?, ?)
                    """,
                    (
                        session_id,
                        patient_id,
                        preferred_hand,
                        notes,
                        int(eeg_enabled_at_start),
                        timestamp,
                        timestamp,
                        timestamp,
                    ),
                )
        except sqlite3.IntegrityError as exc:
            shutil.rmtree(directory, ignore_errors=True)
            raise ActiveSessionExistsError("Inna sesja jest już aktywna") from exc
        except Exception:
            shutil.rmtree(directory, ignore_errors=True)
            raise

        session = self.get_session(session_id)
        self._write_session_metadata(session)
        return self.summary(session_id)

    def recover_active_sessions(self) -> list[str]:
        now = utc_now()
        timestamp = isoformat(now)
        recovered: list[str] = []
        with self._connect() as connection:
            rows = connection.execute(
                "SELECT id, started_at FROM sessions WHERE status = 'active'"
            ).fetchall()
            for row in rows:
                duration_ms = max(
                    0,
                    int((now - parse_timestamp(row["started_at"])).total_seconds() * 1000),
                )
                connection.execute(
                    """
                    UPDATE sessions
                    SET status = 'interrupted', ended_at = ?, duration_ms = ?,
                        recovery_pending = 1, updated_at = ?
                    WHERE id = ?
                    """,
                    (timestamp, duration_ms, timestamp, row["id"]),
                )
                recovered.append(row["id"])
        for session_id in recovered:
            self.reconcile_stream_counts(session_id)
            self._write_session_metadata(self.get_session(session_id))
        return recovered

    def get_active_session(self) -> dict[str, Any] | None:
        with self._connect() as connection:
            row = connection.execute(
                "SELECT * FROM sessions WHERE status = 'active'"
            ).fetchone()
        return dict(row) if row is not None else None

    def take_recovered_session(self) -> dict[str, Any] | None:
        with self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            row = connection.execute(
                """
                SELECT id FROM sessions
                WHERE status = 'interrupted' AND recovery_pending = 1
                ORDER BY ended_at DESC
                LIMIT 1
                """
            ).fetchone()
            if row is None:
                return None
            session_id = row["id"]
            connection.execute(
                """
                UPDATE sessions
                SET recovery_pending = 0, updated_at = ?
                WHERE id = ?
                """,
                (isoformat(utc_now()), session_id),
            )
        return self.summary(session_id)

    def get_session(self, session_id: str) -> dict[str, Any]:
        with self._connect() as connection:
            row = connection.execute(
                "SELECT * FROM sessions WHERE id = ?",
                (session_id,),
            ).fetchone()
        if row is None:
            raise SessionNotFoundError(f"Nie znaleziono sesji {session_id}")
        return dict(row)

    def end_session(
        self,
        session_id: str,
        *,
        status: str = "completed",
    ) -> dict[str, Any]:
        if status not in {"completed", "interrupted"}:
            raise ValueError(f"Unsupported final session status: {status}")
        now = utc_now()
        timestamp = isoformat(now)
        already_finished = False
        with self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            row = connection.execute(
                "SELECT * FROM sessions WHERE id = ?",
                (session_id,),
            ).fetchone()
            if row is None:
                raise SessionNotFoundError(f"Nie znaleziono sesji {session_id}")
            if row["status"] != "active":
                already_finished = True
            else:
                duration_ms = max(
                    0,
                    int(
                        (now - parse_timestamp(row["started_at"])).total_seconds()
                        * 1000
                    ),
                )
                connection.execute(
                    """
                    UPDATE sessions
                    SET status = ?, ended_at = ?, duration_ms = ?,
                        recovery_pending = ?, updated_at = ?
                    WHERE id = ?
                    """,
                    (
                        status,
                        timestamp,
                        duration_ms,
                        1 if status == "interrupted" else 0,
                        timestamp,
                        session_id,
                    ),
                )
        if already_finished:
            return self.summary(session_id)
        session = self.get_session(session_id)
        self._write_session_metadata(session)
        return self.summary(session_id)

    def update_post_session_notes(
        self,
        session_id: str,
        notes: str,
    ) -> dict[str, Any]:
        with self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            session = connection.execute(
                "SELECT status FROM sessions WHERE id = ?",
                (session_id,),
            ).fetchone()
            if session is None:
                raise SessionNotFoundError(f"Nie znaleziono sesji {session_id}")
            if session["status"] == "active":
                raise SessionStateError(
                    "Notatki po sesji można zapisać dopiero po jej zakończeniu"
                )
            connection.execute(
                """
                UPDATE sessions
                SET post_session_notes = ?, updated_at = ?
                WHERE id = ?
                """,
                (notes, isoformat(utc_now()), session_id),
            )
        session_data = self.get_session(session_id)
        self._write_session_metadata(session_data)
        return self.summary(session_id)

    def add_event(
        self,
        session_id: str,
        *,
        label: str,
        category: str,
        note: str,
        source: str = "clinician",
    ) -> dict[str, Any]:
        now = utc_now()
        timestamp = isoformat(now)
        event_id = str(uuid.uuid4())
        with self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            session = connection.execute(
                "SELECT status, started_at FROM sessions WHERE id = ?",
                (session_id,),
            ).fetchone()
            if session is None:
                raise SessionNotFoundError(f"Nie znaleziono sesji {session_id}")
            if session["status"] != "active":
                raise SessionStateError(
                    "Zdarzenia można dodawać tylko do aktywnej sesji"
                )
            elapsed_ms = max(
                0,
                int(
                    (now - parse_timestamp(session["started_at"])).total_seconds()
                    * 1000
                ),
            )
            connection.execute(
                """
                INSERT INTO session_events (
                    id, session_id, label, category, note,
                    occurred_at, elapsed_ms, source
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    event_id,
                    session_id,
                    label,
                    category,
                    note,
                    timestamp,
                    elapsed_ms,
                    source,
                ),
            )
            connection.execute(
                """
                UPDATE sessions
                SET session_events = session_events + 1, updated_at = ?
                WHERE id = ?
                """,
                (timestamp, session_id),
            )

        event = {
            "id": event_id,
            "label": label,
            "category": category,
            "note": note,
            "occurred_at": timestamp,
            "elapsed_ms": elapsed_ms,
            "source": source,
        }
        self._append_lines(
            self.session_directory(session_id) / "session_events.ndjson",
            [event],
        )
        return event

    def append_records(
        self,
        session_id: str,
        records: Iterable[tuple[str, dict[str, Any]]],
        *,
        dropped_records: int = 0,
    ) -> None:
        grouped: dict[str, list[dict[str, Any]]] = {
            stream: [] for stream in STREAM_FILES
        }
        for stream, record in records:
            if stream not in STREAM_FILES:
                raise ValueError(f"Unsupported session stream: {stream}")
            grouped[stream].append(record)

        increments = {stream: len(values) for stream, values in grouped.items()}
        for stream, values in grouped.items():
            if values:
                self._append_lines(
                    self.session_directory(session_id) / STREAM_FILES[stream],
                    values,
                )

        assignments = [
            f"{column} = {column} + ?" for column in COUNT_COLUMNS if increments[column]
        ]
        values = [increments[column] for column in COUNT_COLUMNS if increments[column]]
        if dropped_records:
            assignments.append("dropped_records = dropped_records + ?")
            values.append(dropped_records)
        if not assignments:
            return
        assignments.append("updated_at = ?")
        values.extend((isoformat(utc_now()), session_id))
        with self._connect() as connection:
            connection.execute(
                f"UPDATE sessions SET {', '.join(assignments)} WHERE id = ?",
                values,
            )

    def record_drops(self, session_id: str, count: int) -> None:
        if count <= 0:
            return
        with self._connect() as connection:
            connection.execute(
                """
                UPDATE sessions
                SET dropped_records = dropped_records + ?, updated_at = ?
                WHERE id = ?
                """,
                (count, isoformat(utc_now()), session_id),
            )

    def reconcile_stream_counts(self, session_id: str) -> None:
        self.get_session(session_id)
        directory = self.session_directory(session_id)
        counts = {
            stream: self._count_records(directory / filename)
            for stream, filename in STREAM_FILES.items()
        }
        with self._connect() as connection:
            connection.execute(
                """
                UPDATE sessions
                SET eeg_records = ?, eye_tracking_records = ?,
                    vr_events = ?, vr_frames = ?, updated_at = ?
                WHERE id = ?
                """,
                (
                    counts["eeg_records"],
                    counts["eye_tracking_records"],
                    counts["vr_events"],
                    counts["vr_frames"],
                    isoformat(utc_now()),
                    session_id,
                ),
            )

    def events(self, session_id: str) -> list[dict[str, Any]]:
        self.get_session(session_id)
        with self._connect() as connection:
            rows = connection.execute(
                """
                SELECT id, label, category, note, occurred_at, elapsed_ms, source
                FROM session_events
                WHERE session_id = ?
                ORDER BY elapsed_ms, occurred_at
                """,
                (session_id,),
            ).fetchall()
        return [dict(row) for row in rows]

    def summary(self, session_id: str) -> dict[str, Any]:
        session = self.get_session(session_id)
        duration_ms = session["duration_ms"]
        if duration_ms is None and session["status"] == "active":
            duration_ms = max(
                0,
                int(
                    (
                        utc_now() - parse_timestamp(session["started_at"])
                    ).total_seconds()
                    * 1000
                ),
            )
        return {
            "session_id": session["id"],
            "patient_id": session["patient_id"],
            "preferred_hand": session["preferred_hand"],
            "notes": session["notes"],
            "post_session_notes": session["post_session_notes"],
            "eeg_enabled_at_start": bool(session["eeg_enabled_at_start"]),
            "status": session["status"],
            "started_at": session["started_at"],
            "ended_at": session["ended_at"],
            "duration_seconds": (
                duration_ms / 1000.0 if duration_ms is not None else None
            ),
            "counts": {
                "eeg_records": session["eeg_records"],
                "eye_tracking_records": session["eye_tracking_records"],
                "vr_events": session["vr_events"],
                "vr_frames": session["vr_frames"],
                "session_events": session["session_events"],
            },
            "dropped_records": session["dropped_records"],
            "session_events": self.events(session_id),
        }

    def create_raw_archive(self, session_id: str, export_dir: Path) -> Path:
        summary = self.summary(session_id)
        directory = self.session_directory(session_id)
        export_dir.mkdir(parents=True, exist_ok=True)
        temporary = tempfile.NamedTemporaryFile(
            prefix=f"raw_data_{session_id}_",
            suffix=".zip",
            dir=export_dir,
            delete=False,
        )
        archive_path = Path(temporary.name)
        temporary.close()
        with zipfile.ZipFile(
            archive_path,
            mode="w",
            compression=zipfile.ZIP_DEFLATED,
            compresslevel=6,
        ) as archive:
            archive.writestr(
                "session.json",
                json.dumps(summary, ensure_ascii=False, indent=2) + "\n",
            )
            for filename in (*STREAM_FILES.values(), "session_events.ndjson"):
                if filename == "session_events.ndjson":
                    archive.writestr(
                        filename,
                        "".join(
                            json.dumps(
                                event,
                                ensure_ascii=False,
                                separators=(",", ":"),
                            )
                            + "\n"
                            for event in summary["session_events"]
                        ),
                    )
                    continue
                path = directory / filename
                if path.is_file():
                    archive.write(path, filename)
        return archive_path

    def session_directory(self, session_id: str) -> Path:
        return self.session_root / session_id

    def _write_session_metadata(self, session: dict[str, Any]) -> None:
        directory = self.session_directory(session["id"])
        directory.mkdir(parents=True, exist_ok=True)
        path = directory / "session.json"
        path.write_text(
            json.dumps(session, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )

    def _append_lines(self, path: Path, records: Iterable[dict[str, Any]]) -> None:
        with path.open("a", encoding="utf-8", newline="\n") as output:
            for record in records:
                output.write(
                    json.dumps(record, ensure_ascii=False, separators=(",", ":"))
                )
                output.write("\n")
            output.flush()

    def _count_records(self, path: Path) -> int:
        if not path.is_file():
            return 0
        with path.open("rb") as source:
            return sum(1 for line in source if line.strip())

    @contextmanager
    def _connect(self) -> Iterator[sqlite3.Connection]:
        connection = sqlite3.connect(
            self.database_path,
            timeout=30,
            isolation_level=None,
        )
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA journal_mode=WAL")
        connection.execute("PRAGMA foreign_keys=ON")
        connection.execute("PRAGMA synchronous=NORMAL")
        try:
            with connection:
                yield connection
        finally:
            connection.close()
