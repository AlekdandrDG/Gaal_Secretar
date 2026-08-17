"""Telegram bot initialization and polling."""

import logging
from collections.abc import Awaitable, Callable
from typing import Any

from aiogram import Bot, Dispatcher
from aiogram.client.default import DefaultBotProperties
from aiogram.client.session.middlewares.base import (
    BaseRequestMiddleware,
    NextRequestMiddlewareType,
)
from aiogram.enums import ParseMode
from aiogram.fsm.storage.memory import MemoryStorage
from aiogram.methods import EditMessageText, SendMessage
from aiogram.methods.base import Response, TelegramMethod, TelegramType
from aiogram.types import Update

from d_brain.config import Settings
from d_brain.services.security import redact_secrets

logger = logging.getLogger(__name__)

ACCESS_DENIED_TEXT = (
    "🚫 Это личный ассистент. Доступ только у владельца.\n\n"
    "Если бот нужен вам — разверните свою копию: "
    "исходники открыты."
)


class RedactionMiddleware(BaseRequestMiddleware):
    """Outbound gate: каждый исходящий текст проходит редактор секретов."""

    async def __call__(
        self,
        make_request: NextRequestMiddlewareType[TelegramType],
        bot: Bot,
        method: TelegramMethod[TelegramType],
    ) -> Response[TelegramType]:
        if isinstance(method, (SendMessage, EditMessageText)) and method.text:
            clean = redact_secrets(method.text)
            if clean != method.text:
                method = method.model_copy(update={"text": clean})
        return await make_request(bot, method)


def create_bot(settings: Settings) -> Bot:
    bot = Bot(
        token=settings.telegram_bot_token,
        default=DefaultBotProperties(parse_mode=ParseMode.HTML),
    )
    bot.session.middleware(RedactionMiddleware())
    return bot


def create_dispatcher() -> Dispatcher:
    from d_brain.bot.handlers import (
        achievement,
        buttons,
        calendar_callback,
        commands,
        digest_menu,
        document,
        photo,
        process,
        process_menu,
        text,
        vault_query,
        voice,
        weekly,
    )

    dp = Dispatcher(storage=MemoryStorage())

    dp.include_router(commands.router)
    dp.include_router(achievement.router)
    dp.include_router(process.router)
    dp.include_router(process_menu.router)
    dp.include_router(weekly.router)
    dp.include_router(vault_query.router)
    dp.include_router(buttons.router)
    dp.include_router(calendar_callback.router)
    dp.include_router(digest_menu.router)
    dp.include_router(voice.router)
    dp.include_router(photo.router)
    dp.include_router(document.router)
    dp.include_router(text.router)
    return dp


MiddlewareHandler = Callable[[Update, dict[str, Any]], Awaitable[Any]]
MiddlewareType = Callable[[MiddlewareHandler, Update, dict[str, Any]], Awaitable[Any]]


def _extract_user_id(event: Update) -> int | None:
    """Pull the acting user's Telegram id out of any update type we serve."""
    user = getattr(event, "event", None)
    from_user = getattr(user, "from_user", None)
    if from_user is not None:
        return from_user.id
    # Fallback for update kinds where `event.event` is not populated.
    for field in ("message", "edited_message", "callback_query", "inline_query"):
        obj = getattr(event, field, None)
        if obj is not None and getattr(obj, "from_user", None) is not None:
            return obj.from_user.id
    return None


def create_auth_middleware(settings: Settings) -> MiddlewareType:
    """Allow-list gate: only `allowed_user_ids` reach the handlers.

    This is the ONLY access control in the bot — every update passes through it
    before routing. Non-allowed users get a refusal and the handler is never
    called. An empty allow-list means nobody gets in unless `allow_all_users`
    is explicitly turned on.
    """

    allowed = set(settings.allowed_user_ids)
    allow_all = settings.allow_all_users

    if allow_all:
        logger.warning(
            "ALLOW_ALL_USERS=true — bot is open to everyone. "
            "Use only for local testing."
        )
    elif not allowed:
        logger.warning(
            "ALLOWED_USER_IDS is empty — bot will reject every user. "
            "Put your Telegram user id in .env."
        )

    async def auth_middleware(
        handler: Callable[[Update, dict[str, Any]], Awaitable[Any]],
        event: Update,
        data: dict[str, Any],
    ) -> Any:
        if allow_all:
            return await handler(event, data)

        user_id = _extract_user_id(event)
        if user_id is not None and user_id in allowed:
            return await handler(event, data)

        logger.warning("ACCESS DENIED for user_id=%s", user_id)

        # Tell the intruder once, then stop — handler is NOT called.
        message = getattr(event, "message", None)
        callback = getattr(event, "callback_query", None)
        try:
            if callback is not None:
                await callback.answer(ACCESS_DENIED_TEXT, show_alert=True)
            elif message is not None:
                await message.answer(ACCESS_DENIED_TEXT)
        except Exception:
            logger.debug("Could not deliver access-denied notice", exc_info=True)

        return None

    return auth_middleware


async def run_bot(settings: Settings) -> None:
    bot = create_bot(settings)
    dp = create_dispatcher()
    dp.update.middleware(create_auth_middleware(settings))

    logger.info("Starting bot polling...")
    try:
        await dp.start_polling(bot, allowed_updates=dp.resolve_used_update_types())
    finally:
        await bot.session.close()
