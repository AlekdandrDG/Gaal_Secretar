"""Achievement button handler — capture self-praise to vault/achievements/ + daily file."""

import logging
from datetime import datetime

from aiogram import Bot, F, Router
from aiogram.fsm.context import FSMContext
from aiogram.types import Message

from d_brain.bot.states import AchievementState
from d_brain.config import get_settings
from d_brain.services.achievements import AchievementsStorage
from d_brain.services.storage import VaultStorage
from d_brain.services.transcription import DeepgramTranscriber

logger = logging.getLogger(__name__)
router = Router(name="achievement")


def _save(text: str, ts: datetime, source: str, vault_path) -> int:
    """Write to achievements/YYYY-MM.md AND daily/YYYY-MM-DD.md. Returns month count."""
    ach = AchievementsStorage(vault_path)
    ach.append(text, ts, source=source)

    vault = VaultStorage(vault_path)
    vault.append_to_daily(text, ts, f"[achievement:{source}]")

    return ach.count_this_month(ts)


@router.message(F.text == "🏆 Достижение")
async def btn_achievement(message: Message, state: FSMContext) -> None:
    await state.set_state(AchievementState.waiting_for_input)
    await message.answer(
        "🏆 <b>За что хочешь себя похвалить?</b>\n\n"
        "Отправь голосовое или текст — попадёт в достижения, daily, недельный и месячный отчёты."
    )


@router.message(AchievementState.waiting_for_input, F.voice)
async def capture_voice_achievement(message: Message, state: FSMContext, bot: Bot) -> None:
    settings = get_settings()
    transcriber = DeepgramTranscriber(settings.deepgram_api_key)

    try:
        await message.chat.do(action="typing")
        file = await bot.get_file(message.voice.file_id)
        if not file.file_path:
            await message.answer("Не получилось скачать голосовое")
            return
        file_bytes = await bot.download_file(file.file_path)
        if not file_bytes:
            await message.answer("Не получилось скачать голосовое")
            return

        transcript = await transcriber.transcribe(file_bytes.read())
        if not transcript:
            await message.answer("Не получилось расшифровать")
            return

        ts = datetime.fromtimestamp(message.date.timestamp())
        count = _save(transcript, ts, "voice", settings.vault_path)

        await message.answer(
            f"🏆 <i>{transcript}</i>\n\n"
            f"✓ Сохранено. Достижений за месяц: <b>{count}</b>"
        )
        logger.info("Achievement saved (voice)")
    except Exception as e:
        logger.exception("Achievement voice capture failed")
        await message.answer(f"Ошибка: {e}")
    finally:
        await state.clear()


@router.message(AchievementState.waiting_for_input, F.text)
async def capture_text_achievement(message: Message, state: FSMContext) -> None:
    settings = get_settings()

    try:
        ts = datetime.fromtimestamp(message.date.timestamp())
        count = _save(message.text or "", ts, "text", settings.vault_path)

        await message.answer(
            f"🏆 ✓ Сохранено. Достижений за месяц: <b>{count}</b>"
        )
        logger.info("Achievement saved (text)")
    except Exception as e:
        logger.exception("Achievement text capture failed")
        await message.answer(f"Ошибка: {e}")
    finally:
        await state.clear()
