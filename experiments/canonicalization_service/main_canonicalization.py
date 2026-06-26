import cv2
from dotenv import load_dotenv


if __name__ == '__main__':
    load_dotenv()  # SUPABASE_URL + SUPABASE_KEY from .env

    from canonicalization import CanonicalizationService, InflowSource, CoarseType

    svc = CanonicalizationService.from_supabase()

    val_text = "Ptrickios Farm fresh large Tomatoes"

    svc.print_top_n(val_text, source=InflowSource.PANTRY_SCAN, n=5)

    result = svc.resolve(val_text, source=InflowSource.PANTRY_SCAN)
    print(result.canonical_name, result.matched_via.value, f"{result.confidence:.2f}")

    # With a coarse type from YOLOE (optional — enables veto + boost)
    result = svc.resolve("john west tuna", coarse_type=CoarseType.CAN)