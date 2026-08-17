"""Reply keyboards for Telegram bot."""

from aiogram.types import InlineKeyboardButton, InlineKeyboardMarkup, ReplyKeyboardMarkup
from aiogram.utils.keyboard import ReplyKeyboardBuilder


def get_main_keyboard() -> ReplyKeyboardMarkup:
    """Main reply keyboard with common commands."""
    builder = ReplyKeyboardBuilder()
    # First row: main commands
    builder.button(text="🏆 Достижение")
    builder.button(text="⚙️ Обработать")
    builder.button(text="📅 Дайджест")
    # Second row: vault work
    builder.button(text="🔍 Найти в заметках")
    builder.button(text="🔧 Исправить")
    # Third row
    builder.button(text="❓ Помощь")
    builder.adjust(3, 2, 1)
    return builder.as_markup(resize_keyboard=True, is_persistent=True)


def get_process_menu_keyboard() -> InlineKeyboardMarkup:
    """Inline keyboard for process action selection."""
    return InlineKeyboardMarkup(inline_keyboard=[
        [
            InlineKeyboardButton(text="✅ Задачи", callback_data="pmenu:tasks"),
            InlineKeyboardButton(text="📅 Календарь", callback_data="pmenu:calendar"),
        ],
        [
            InlineKeyboardButton(text="✅📅 Задачи + Календарь", callback_data="pmenu:tasks_cal"),
        ],
        [
            InlineKeyboardButton(text="🧠 Память / Заметки", callback_data="pmenu:memory"),
            InlineKeyboardButton(text="🤝 Итоги встречи", callback_data="pmenu:meeting"),
        ],
    ])


def get_digest_menu_keyboard() -> InlineKeyboardMarkup:
    """Inline submenu for digest period selection."""
    return InlineKeyboardMarkup(inline_keyboard=[
        [
            InlineKeyboardButton(text="📅 Неделя", callback_data="digest:week"),
        ],
    ])
