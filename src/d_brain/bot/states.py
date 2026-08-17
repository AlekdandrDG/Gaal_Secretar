"""Bot FSM states."""

from aiogram.fsm.state import State, StatesGroup


class AchievementState(StatesGroup):
    """States for achievement capture flow."""

    waiting_for_input = State()  # Waiting for voice or text after Achievement button


class VaultSearchState(StatesGroup):
    """States for the vault search flow."""

    waiting_for_query = State()  # Waiting for the search query (text or voice)


class VaultFixState(StatesGroup):
    """States for the vault correction flow."""

    waiting_for_request = State()  # Waiting for the correction request (text or voice)
