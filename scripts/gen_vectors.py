#!/usr/bin/env python3

import argparse
import random
from pathlib import Path

from golden_model import gemm_bias_relu


def twos_complement_hex(value: int, width: int) -> str:
    mask = (1 << width) - 1
    digits = (width + 3) // 4
    return f"{value & mask:0{digits}x}"


def signed_basic_matrices(n: int) -> tuple[list[list[int]], list[list[int]]]:
    if n == 2:
        return (
            [
                [1, 2],
                [3, 4],
            ],
            [
                [5, 6],
                [7, 8],
            ],
        )

    if n == 4:
        return (
            [
                [1, -2, 3, -4],
                [5, 6, -7, 8],
                [-1, 2, -3, 4],
                [7, -8, 9, -10],
            ],
            [
                [2, 0, -1, 3],
                [-4, 5, 6, -7],
                [8, -9, 10, 11],
                [-12, 13, -14, 15],
            ],
        )

    a = [[((row * n + col) % 15) - 7 for col in range(n)] for row in range(n)]
    b = [[(((row + 1) * (col + 3)) % 17) - 8 for col in range(n)] for row in range(n)]
    return a, b


def identity_matrix(n: int) -> list[list[int]]:
    return [[1 if row == col else 0 for col in range(n)] for row in range(n)]


def zero_matrix(n: int) -> list[list[int]]:
    return [[0 for _ in range(n)] for _ in range(n)]


def signed_random_matrices(n: int) -> tuple[list[list[int]], list[list[int]]]:
    rng = random.Random(0x1A57 + n)
    a = [[rng.randint(-128, 127) for _ in range(n)] for _ in range(n)]
    b = [[rng.randint(-128, 127) for _ in range(n)] for _ in range(n)]
    return a, b


def int8_minmax_stress_matrices(n: int) -> tuple[list[list[int]], list[list[int]]]:
    pattern_a = [-128, -127, -64, -1, 0, 1, 63, 64, 126, 127]
    pattern_b = [127, -128, 1, -1, 64, -64, 0, 126, -127, 63]

    a = [
        [pattern_a[(row * n + col) % len(pattern_a)] for col in range(n)]
        for row in range(n)
    ]
    b = [
        [pattern_b[(row + col * n) % len(pattern_b)] for col in range(n)]
        for row in range(n)
    ]
    return a, b


def bias_for_test(n: int, test: str) -> list[int]:
    if test in {
        "signed_basic",
        "identity",
        "zero",
        "signed_random",
        "int8_minmax_stress",
        "bias_zero",
    }:
        return [0 for _ in range(n)]

    if test == "bias_positive":
        return [10 + col for col in range(n)]

    if test == "bias_negative":
        return [-(12 + col) for col in range(n)]

    if test == "relu_basic":
        return [0 for _ in range(n)]

    if test == "signed_random_bias_relu":
        rng = random.Random(0xB1A5 + n)
        return [rng.randint(-2048, 2048) for _ in range(n)]

    raise SystemExit(f"Unsupported TEST={test!r}")


def postprocess_enables_for_test(test: str) -> tuple[bool, bool]:
    if test in {
        "bias_zero",
        "bias_positive",
        "bias_negative",
        "relu_basic",
        "signed_random_bias_relu",
    }:
        return True, True

    return False, False


def matrices_for_test(n: int, test: str) -> tuple[list[list[int]], list[list[int]]]:
    if test == "signed_basic":
        return signed_basic_matrices(n)

    if test == "identity":
        a, _ = signed_basic_matrices(n)
        return a, identity_matrix(n)

    if test == "zero":
        a, _ = signed_basic_matrices(n)
        return a, zero_matrix(n)

    if test == "signed_random":
        return signed_random_matrices(n)

    if test == "int8_minmax_stress":
        return int8_minmax_stress_matrices(n)

    if test == "bias_zero":
        a = [[1 + ((row + col) % 3) for col in range(n)] for row in range(n)]
        b = [[1 + ((row * 2 + col) % 3) for col in range(n)] for row in range(n)]
        return a, b

    if test == "bias_positive":
        return signed_basic_matrices(n)

    if test == "bias_negative":
        a = [[1 for _ in range(n)] for _ in range(n)]
        b = [[1 for _ in range(n)] for _ in range(n)]
        return a, b

    if test == "relu_basic":
        a = [[-1 if col == 0 else 0 for col in range(n)] for _ in range(n)]
        b = [[8 + col for col in range(n)] for _ in range(n)]
        return a, b

    if test == "signed_random_bias_relu":
        return signed_random_matrices(n)

    raise SystemExit(f"Unsupported TEST={test!r}")


def write_matrix_hex(path: Path, matrix: list[list[int]], width: int) -> None:
    lines = [
        twos_complement_hex(matrix[row][col], width)
        for row in range(len(matrix))
        for col in range(len(matrix))
    ]
    path.write_text("\n".join(lines) + "\n", encoding="ascii")


def write_vector_hex(path: Path, values: list[int], width: int) -> None:
    lines = [twos_complement_hex(value, width) for value in values]
    path.write_text("\n".join(lines) + "\n", encoding="ascii")


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate matrix accelerator hex vectors.")
    parser.add_argument("--n", type=int, required=True)
    parser.add_argument("--test", default="signed_basic")
    parser.add_argument("--out-dir", type=Path, required=True)
    args = parser.parse_args()

    if args.n <= 0:
        raise SystemExit("--n must be positive")

    a, b = matrices_for_test(args.n, args.test)
    bias = bias_for_test(args.n, args.test)
    enable_bias, enable_relu = postprocess_enables_for_test(args.test)
    c = gemm_bias_relu(a, b, bias, enable_bias, enable_relu)

    args.out_dir.mkdir(parents=True, exist_ok=True)
    write_matrix_hex(args.out_dir / "A.hex", a, 8)
    write_matrix_hex(args.out_dir / "B.hex", b, 8)
    write_vector_hex(args.out_dir / "bias.hex", bias, 32)
    write_matrix_hex(args.out_dir / "C_expected.hex", c, 32)

    print(f"Generated {args.test} vectors for N={args.n} in {args.out_dir}")


if __name__ == "__main__":
    main()
