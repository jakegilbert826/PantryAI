from dotenv import load_dotenv


if __name__ == '__main__':
    load_dotenv()  # SUPABASE_URL + SUPABASE_KEY from .env

    from canonicalization import CanonicalizationService, InflowSource, LineInput

    svc = CanonicalizationService.from_supabase()

    # A can of corn kernels: the product name is two small lines drowned in the
    # nutrition panel / marketing copy. Each line carries its bbox prominence.
    lines = [
        LineInput("420 g", 0.45),
        LineInput("nels 1 serve of vegetables = 1/2 a cup", 0.30),
        LineInput("No Artificial Sugars, Flavours or Preservatives", 0.25),
        LineInput("5 HEALTH STAR RATING", 0.40),
        LineInput("Part of your daily", 0.20),
        LineInput("Corn Kernels", 0.95),  # the actual product name — tallest text
    ]

    print("=== blob (legacy: all lines joined, one Dice denominator) ===")
    blob = " ".join(l.text for l in lines)
    svc.print_top_n(blob, source=InflowSource.PANTRY_SCAN, n=5)

    print("\n=== per-line + prominence ===")
    svc.print_top_n_lines(lines, source=InflowSource.PANTRY_SCAN, n=5)

    result = svc.resolve_lines(lines, source=InflowSource.PANTRY_SCAN)
    print("\nbest:", result.canonical_name, result.matched_via.value, f"{result.confidence:.2f}")
