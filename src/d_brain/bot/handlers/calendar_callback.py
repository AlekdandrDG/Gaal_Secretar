"""Inline keyboard callback handler for calendar actions."""

import asyncio
import logging

from aiogram import Router
from aiogram.types import CallbackQuery

from d_brain.config import get_settings
from d_brain.services.processor import ClaudeProcessor

router = Router(name="calendar_callback")
logger = logging.getLogger(__name__)

_BINARY_SUFFIXES = {".pdf", ".jpg", ".jpeg", ".png", ".gif", ".webp"}


@router.callback_query(lambda c: c.data and c.data.startswith("cal:"))
async def handle_calendar_callback(callback: CallbackQuery) -> None:
    """Handle 'В календарь' button press."""
    if not callback.data or not callback.message:
        return

    relative_path = callback.data[4:]  # strip "cal:"

    settings = get_settings()
    file_path = settings.vault_path / relative_path

    if not file_path.exists():
        await callback.answer("❌ Файл не найден", show_alert=True)
        return

    await callback.answer()
    await callback.message.edit_text("⏳ Анализирую для календаря...")

    processor = ClaudeProcessor(settings.vault_path)

    is_binary = file_path.suffix.lower() in _BINARY_SUFFIXES

    if not is_binary:
        # Check if already processed (text files only — binary files use sidecar via processor)
        content = file_path.read_text(encoding="utf-8")
        if "calendar_processed: true" in content:
            await callback.message.edit_text("ℹ️ Эти события уже добавлены в календарь ранее.", reply_markup=None)
            return
    else:
        content = ""

    result = await asyncio.to_thread(
        processor.analyze_file_for_calendar,
        file_path,
    )

    if "error" in result:
        await callback.message.edit_text(f"❌ Ошибка: {result['error']}", reply_markup=None)
    else:
        if not is_binary:
            # Mark text file as processed via frontmatter
            if content.startswith("---"):
                marked = content.replace("---\n", "---\ncalendar_processed: true\n", 1)
            else:
                marked = "---\ncalendar_processed: true\n---\n" + content
            file_path.write_text(marked, encoding="utf-8")

        report = result.get("report", "Готово")
        try:
            await callback.message.edit_text(report, reply_markup=None)
        except Exception:
            await callback.message.edit_text(report, parse_mode=None, reply_markup=None)

    logger.info("Calendar analysis done for %s", relative_path)
