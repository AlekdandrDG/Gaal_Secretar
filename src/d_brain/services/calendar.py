"""Google Calendar API wrapper — direct service account access."""

from __future__ import annotations

import logging
import socket
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

from google.oauth2.service_account import Credentials
from googleapiclient.discovery import build

logger = logging.getLogger(__name__)

SCOPES = ["https://www.googleapis.com/auth/calendar"]


# Some hosts have broken IPv6 routing: Google API hosts resolve to both A and
# AAAA records, and httplib2 (used by the Google client) hangs on the IPv6
# socket.connect() until timeout. Force all DNS resolution to IPv4 so calendar
# calls connect instantly. Idempotent — applied once at import time.
def _force_ipv4() -> None:
    _orig_getaddrinfo = socket.getaddrinfo

    if getattr(_orig_getaddrinfo, "_ipv4_forced", False):
        return

    def _ipv4_getaddrinfo(host, port, family=0, *args, **kwargs):
        return _orig_getaddrinfo(host, port, socket.AF_INET, *args, **kwargs)

    _ipv4_getaddrinfo._ipv4_forced = True
    socket.getaddrinfo = _ipv4_getaddrinfo


_force_ipv4()


class CalendarClient:
    """Direct Google Calendar access via service account.

    The target calendar (GOOGLE_CALENDAR_ID) must be shared with the service
    account email (editor role) in Google Calendar settings.
    """

    def __init__(self, credentials_path: Path, calendar_id: str = "primary") -> None:
        creds = Credentials.from_service_account_file(
            str(credentials_path), scopes=SCOPES
        )
        self.service = build("calendar", "v3", credentials=creds)
        self.calendar_id = calendar_id

    def create_event(
        self,
        summary: str,
        start_time: str,
        end_time: str,
        description: str = "",
        location: str = "",
        timezone: str = "Europe/Moscow",
        recurrence: list[str] | None = None,
    ) -> dict[str, Any]:
        """Create a calendar event.

        Args:
            summary: Event title
            start_time: ISO format YYYY-MM-DDTHH:MM:SS
            end_time: ISO format YYYY-MM-DDTHH:MM:SS
            description: Optional event description
            timezone: Timezone string (default: Europe/Moscow)

        Returns:
            Created event dict from Google API
        """
        body: dict[str, Any] = {
            "summary": summary,
            "start": {"dateTime": start_time, "timeZone": timezone},
            "end": {"dateTime": end_time, "timeZone": timezone},
        }
        if description:
            body["description"] = description
        if location:
            body["location"] = location
        if recurrence:
            # e.g. ["RRULE:FREQ=DAILY;UNTIL=20260612T000000Z"]
            body["recurrence"] = recurrence

        event = (
            self.service.events()
            .insert(calendarId=self.calendar_id, body=body)
            .execute()
        )
        logger.info("Created event: %s (%s)", summary, event.get("id"))
        return event

    def create_events_from_list(
        self, events: list[dict[str, Any]]
    ) -> tuple[list[dict], list[tuple[dict, str]]]:
        """Create multiple events, return (created, failed) lists.

        Each event dict must have: summary, start_time, end_time.
        Optional: description.
        """
        created = []
        failed = []
        for ev in events:
            try:
                result = self.create_event(
                    summary=ev.get("summary", ""),
                    start_time=ev.get("start_time", ""),
                    end_time=ev.get("end_time", ""),
                    description=ev.get("description", ""),
                    location=ev.get("location", ""),
                    recurrence=ev.get("recurrence") or None,
                )
                created.append({**ev, "_event_id": result.get("id")})
            except Exception as exc:
                logger.error("Failed to create event %s: %s", ev.get("summary"), exc)
                failed.append((ev, str(exc)))
        return created, failed
