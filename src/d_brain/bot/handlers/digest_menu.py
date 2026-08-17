"""Inline-submenu callbacks for digest period selection."""

import logging

from aiogram import Router
from aiogram.types import CallbackQuery

router = Router(name="digest_menu")
logger = logging.getLogger(__name__)


@router.callback_query(lambda c: c.data and c.data.startswith("digest:"))
async def handle_digest_choice(callback: CallbackQuery) -> None:
    """Route digest choice (day/week/month) to corresponding command handler."""
    if not callback.data or not callback.message:
        return

    period = callback.data[len("digest:"):]
    await callback.answer()
    try:
        await callback.message.edit_reply_markup(reply_markup=None)
    except Exception:
        pass

    if period == "week":
        from d_brain.bot.handlers.weekly import cmd_weekly

        await cmd_weekly(callback.message)
    else:
        await callback.message.answer(f"❓ Неизвестный период: {period}")

    logger.info("Digest period chosen: %s", period)
