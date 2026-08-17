"""Document/file message handler."""

import logging
from datetime import datetime

from aiogram import Bot, Router
from aiogram.types import InlineKeyboardButton, InlineKeyboardMarkup, Message

from d_brain.config import get_settings
from d_brain.services.session import SessionStore
from d_brain.services.storage import VaultStorage

router = Router(name="document")
logger = logging.getLogger(__name__)

SUPPORTED_EXTENSIONS = {"pdf", "jpg", "jpeg", "png", "gif", "webp"}


@router.message(lambda m: m.document is not None)
async def handle_document(message: Message, bot: Bot) -> None:
    """Handle document/file messages."""
    if not message.document or not message.from_user:
        return

    doc = message.document
    filename = doc.file_name or "file"
    extension = filename.rsplit(".", 1)[-1].lower() if "." in filename else "bin"

    settings = get_settings()
    storage = VaultStorage(settings.vault_path)

    try:
        file = await bot.get_file(doc.file_id)
        if not file.file_path:
            await message.answer("❌ Не удалось скачать файл")
            return

        file_bytes = await bot.download_file(file.file_path)
        if not file_bytes:
            await message.answer("❌ Не удалось скачать файл")
            return

        timestamp = datetime.fromtimestamp(message.date.timestamp())
        data = file_bytes.read()

        relative_path = storage.save_attachment(
            data,
            timestamp.date(),
            timestamp,
            extension,
        )

        # Add to daily note
        content = f"📎 [{filename}]({relative_path})"
        if message.caption:
            content += f"\n\n{message.caption}"
        storage.append_to_daily(content, timestamp, "[document]")

        session = SessionStore(settings.vault_path)
        session.append(
            message.from_user.id,
            "document",
            path=relative_path,
            filename=filename,
            caption=message.caption,
            msg_id=message.message_id,
        )

        # Offer calendar analysis for supported formats
        if extension in SUPPORTED_EXTENSIONS:
            callback_data = f"cal:{relative_path}"
            keyboard = InlineKeyboardMarkup(inline_keyboard=[[
                InlineKeyboardButton(text="📅 В календарь", callback_data=callback_data)
            ]])
            await message.answer(f"📎 ✓ Сохранено ({filename})", reply_markup=keyboard)
        else:
            await message.answer(f"📎 ✓ Сохранено ({filename})")

        logger.info("Document saved: %s", relative_path)

    except Exception as e:
        logger.exception("Error processing document")
        await message.answer(f"Error: {e}")
