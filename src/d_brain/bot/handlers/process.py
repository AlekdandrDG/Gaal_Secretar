"""Process command handler."""

import logging

from aiogram import Router
from aiogram.filters import Command
from aiogram.types import Message

from d_brain.bot.keyboards import get_process_menu_keyboard

router = Router(name="process")
logger = logging.getLogger(__name__)


@router.message(Command("process"))
async def cmd_process(message: Message) -> None:
    """Handle /process command - show action menu."""
    user_id = message.from_user.id if message.from_user else "unknown"
    logger.info("Process command triggered by user %s", user_id)

    await message.answer(
        "⚙️ <b>Что сделать с записями?</b>\n\nВыбери действие:",
        reply_markup=get_process_menu_keyboard(),
    )
