from app.config.settings import settings
from app.service import MiniPcService
from app.utils.logger import setup_logging


def main() -> None:
    setup_logging(settings.log_level)
    service = MiniPcService()
    service.start_forever()


if __name__ == '__main__':
    main()
