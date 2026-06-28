import os
import glob
from pathlib import Path
import cv2
from ultralytics import YOLOE

# 1. Configuration
DATA = Path(__file__).resolve().parents[2] / "data"  # .../experiments/data
IMAGE_DIR = str(DATA / "cv_input")  # Folder containing your test pictures
OUTPUT_DIR = str(DATA / "cv_output")  # Where the isolated items will be saved
CONFIDENCE_THRESHOLD = 0.4  # Adjust this to filter out noise or catch more items

os.makedirs(OUTPUT_DIR, exist_ok=True)

# 2. Load the Open-Vocabulary, Prompt-Free Nano Model
print("Downloading/Loading YOLOE-26 Nano Prompt-Free weights...")
model = YOLOE(str(DATA / "models" / "yoloe-26n-seg-pf.pt"))

# 3. Grab all image files from your directory
image_extensions = ("*.jpg", "*.jpeg", "*.png", "*.BMP")
image_paths = []
for ext in image_extensions:
    image_paths.extend(glob.glob(os.path.join(IMAGE_DIR, ext)))

if not image_paths:
    print(f"No images found in {IMAGE_DIR}. Please add some test photos.")
    exit()

print(f"Found {len(image_paths)} images to process for QA.\n" + "-" * 50)

# 4. Loop through each image
for img_idx, img_path in enumerate(image_paths):
    filename = os.path.basename(img_path)
    print(f"Processing [{img_idx + 1}/{len(image_paths)}]: {filename}")

    # Load raw image with OpenCV for cropping / plotting
    orig_img = cv2.imread(img_path)
    if orig_img is None:
        print(f"Skipping unreadable image: {filename}")
        continue

    # Run the prompt-free inference
    results = model.predict(source=img_path, conf=CONFIDENCE_THRESHOLD, verbose=False)
    result = results[0]

    # Create a clean copy to draw the QA overlay onto
    overlay_img = orig_img.copy()

    # 5. Extract boxes
    if len(result.boxes) == 0:
        print(f" -> No items detected in {filename}")
        continue

    for box_idx, box in enumerate(result.boxes):
        # Coordinates format: [xmin, ymin, xmax, ymax]
        xyxy = box.xyxy[0].cpu().numpy().astype(int)
        xmin, ymin, xmax, ymax = xyxy

        # Clip coordinates to image boundary dimensions
        h, w, _ = orig_img.shape
        xmin, xmax = max(0, xmin), min(w, xmax)
        ymin, ymax = max(0, ymin), min(h, ymax)

        cls_id = int(box.cls[0].item())
        label = result.names[cls_id]  # e.g. "apple", "bottle", "can"
        conf = float(box.conf[0].item())

        # Check to ensure valid crop area
        if (xmax - xmin) <= 0 or (ymax - ymin) <= 0:
            continue

        # Draw bounding box overlay for visual inspection
        cv2.rectangle(overlay_img, (xmin, ymin), (xmax, ymax), (0, 255, 0), 2)
        cv2.putText(overlay_img, f"{label} {conf:.2f}", (xmin, ymin - 8),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 1)

        # Isolate and crop the item out of the raw frame
        cropped_item = orig_img[ymin:ymax, xmin:xmax]

        # Save the isolated item box to disk
        base_name_without_ext = os.path.splitext(filename)[0]
        crop_filename = f"{base_name_without_ext}_box_{box_idx}.jpg"
        # cv2.imwrite(os.path.join(OUTPUT_DIR, crop_filename), cropped_item)

    # Save the master QA overlay image showing all detections
    qa_overlay_filename = f"QA_OVERLAY_{filename}"
    cv2.imwrite(os.path.join(OUTPUT_DIR, qa_overlay_filename), overlay_img)

    print(f" -> Successfully mapped {len(result.boxes)} items. Saved crops and overlay to '{OUTPUT_DIR}'")

print("\n" + "=" * 50 + "\nQA Processing complete! Check your output folder to verify the box placements.")