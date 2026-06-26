"""
QA harness for the segmentation service: run detection over a folder of
images, save each crop plus a labelled overlay to an output directory.

This is a thin demo on top of SegmentationService — the reusable logic lives
in segmentation.py.
"""

from pathlib import Path

import cv2

from segmentation import SegmentationService

IMAGE_DIR = Path("../cv_input")
OUTPUT_DIR = Path("../cv_output")
MODEL_PATH = Path("../models/yoloe-26n-seg.pt")
CLASSES = ["product", "produce"]
CONFIDENCE_THRESHOLD = 0.2


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    svc = SegmentationService(MODEL_PATH, classes=CLASSES,
                              confidence_threshold=CONFIDENCE_THRESHOLD)

    image_paths = svc.list_images(IMAGE_DIR)
    if not image_paths:
        print(f"No images found in {IMAGE_DIR}.")
        return

    print(f"Found {len(image_paths)} images to process for QA.\n" + "-" * 50)

    for idx, img_path in enumerate(image_paths, 1):
        print(f"Processing [{idx}/{len(image_paths)}]: {img_path.name}")
        image = svc.read(img_path)
        detections = svc.segment_array(image, source=str(img_path))

        if not detections:
            print(f" -> No items detected in {img_path.name}")
            continue

        for det in detections:
            crop_name = f"{img_path.stem}_box_{det.box_id}.jpg"
            cv2.imwrite(str(OUTPUT_DIR / crop_name), det.crop)

        overlay = svc.draw_overlay(image, detections)
        cv2.imwrite(str(OUTPUT_DIR / f"QA_OVERLAY_{img_path.name}"), overlay)
        print(f" -> Mapped {len(detections)} items. Saved crops + overlay to '{OUTPUT_DIR}'")

    print("\n" + "=" * 50 + "\nQA processing complete.")


if __name__ == "__main__":
    main()
