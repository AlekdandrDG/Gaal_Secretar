"""Button handlers for reply keyboard."""

from aiogram import F, Router
from aiogram.types import Message

router = Router(name="buttons")


@router.message(F.text == "⚙️ Обработать")
async def btn_process(message: Message) -> None:
    """Handle Process button."""
    from d_brain.bot.handlers.process import cmd_process

    await cmd_process(message)


@router.message(F.text == "📅 Дайджест")
async def btn_digest(message: Message) -> None:
    """Handle Digest button — show digest submenu."""
    from d_brain.bot.keyboards import get_digest_menu_keyboard

    await message.answer(
        "🗂 <b>Какой дайджест?</b>",
        reply_markup=get_digest_menu_keyboard(),
    )


@router.message(F.text == "❓ Помощь")
async def btn_help(message: Message) -> None:
    """Handle Help button."""
    from d_brain.bot.handlers.commands import cmd_help

    await cmd_help(message)
