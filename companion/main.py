"""
This script is designed to monitor a specified folder for new TGA (Truevision TGA) screenshot files.
When a new TGA file is detected, it sends a desktop notification and then deletes the screenshot file.
Additionally, it cleans up any existing TGA files in the specified folder when the script starts.

Update the `SCREENSHOT_FOLDER` constant to the folder where your TGA screenshots are saved.

Run the script:

pip install -r requirements.txt
python main.py
"""

SCREENSHOT_FOLDER: str = "D:\\World of Warcraft\\_retail_\\Screenshots"  # change to your wow folder
FILE_EXTENSION: str = ".tga"

import logging
import os
import time
from contextlib import contextmanager
from typing import Any, Iterator

from notifier import Notifier
from watchdog.events import FileSystemEventHandler
from watchdog.observers import Observer

logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")


class ScreenshotHandler(FileSystemEventHandler):
    def on_created(self, event) -> None:
        if event.is_directory or not event.src_path.endswith(FILE_EXTENSION):
            return
        logging.info(f"TGA file detected: {event.src_path}")
        self.notify_new_screenshot()
        self.delete_screenshot(event.src_path)

    @staticmethod
    def notify_new_screenshot() -> None:
        notifier = Notifier()
        notifier.title = "Queue Ready"
        notifier.message = "Your queue is ready. Check in game."

        notifier.send()

    @staticmethod
    def delete_screenshot(file_path: str) -> None:
        try:
            os.remove(file_path)
            logging.info(f"Deleted screenshot: {file_path}")
        except OSError as e:
            logging.error(f"Error deleting file {file_path}: {e}")


def remove_old_screenshots(folder: str) -> None:
    for file_name in os.listdir(folder):
        if file_name.endswith(FILE_EXTENSION):
            try:
                os.remove(os.path.join(folder, file_name))
                logging.info(f"Removed old screenshot: {file_name}")
            except OSError as e:
                logging.error(f"Failed to remove old screenshot {file_name}: {e}")


@contextmanager
def setup_observer(folder: str, handler: FileSystemEventHandler) -> Iterator[Any]:
    observer = Observer()
    observer.schedule(handler, folder, recursive=False)
    observer.start()
    try:
        yield observer
    finally:
        observer.stop()
        observer.join()


def main() -> None:
    if not os.path.exists(SCREENSHOT_FOLDER):
        logging.error(f"Specified folder does not exist: {SCREENSHOT_FOLDER}")
        return

    remove_old_screenshots(SCREENSHOT_FOLDER)

    event_handler = ScreenshotHandler()

    try:
        with setup_observer(SCREENSHOT_FOLDER, event_handler):
            logging.info(f"Observer started, watching {SCREENSHOT_FOLDER}")
            # Keep the script running to monitor for new screenshots
            while True:
                time.sleep(1)
    except Exception as e:
        logging.error(f"An unexpected error occurred: {e}")


if __name__ == "__main__":
    main()
