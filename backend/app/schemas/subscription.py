from datetime import datetime

from pydantic import BaseModel


class SubscriptionOut(BaseModel):
    is_premium: bool
    expires_at: datetime | None
    cancel_at_period_end: bool
