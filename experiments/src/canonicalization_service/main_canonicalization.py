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

    # A can of black beans whose name is split across two large-text lines.
    # Per line, "Black" alone scores black_tea above black_beans; recombining the
    # two prominent lines into "Black Beans" recovers it (lexical exact).
    split = [
        LineInput("Black", 0.95, order=0),
        LineInput("Beans", 0.92, order=1),
        LineInput("Part of your daily fibre", 0.30, order=2),
    ]
    print("\n=== split name, per-line only (max_combine_lines=1) ===")
    svc.print_top_n_lines(split, source=InflowSource.PANTRY_SCAN, n=3, max_combine_lines=1)
    print("\n=== split name, with recombination ===")
    svc.print_top_n_lines(split, source=InflowSource.PANTRY_SCAN, n=3)
