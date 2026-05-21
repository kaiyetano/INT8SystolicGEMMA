#!/usr/bin/env python3

from __future__ import annotations


def matmul(a: list[list[int]], b: list[list[int]]) -> list[list[int]]:
    n = len(a)
    return [
        [sum(a[row][k] * b[k][col] for k in range(n)) for col in range(n)]
        for row in range(n)
    ]


def apply_bias_relu(
    c: list[list[int]],
    bias: list[int],
    enable_bias: bool,
    enable_relu: bool,
) -> list[list[int]]:
    n = len(c)
    y: list[list[int]] = []

    for row in range(n):
        y_row: list[int] = []
        for col in range(n):
            value = c[row][col]
            if enable_bias:
                value += bias[col]
            if enable_relu and value < 0:
                value = 0
            y_row.append(value)
        y.append(y_row)

    return y


def gemm_bias_relu(
    a: list[list[int]],
    b: list[list[int]],
    bias: list[int] | None = None,
    enable_bias: bool = False,
    enable_relu: bool = False,
) -> list[list[int]]:
    n = len(a)
    if bias is None:
        bias = [0 for _ in range(n)]

    c = matmul(a, b)
    return apply_bias_relu(c, bias, enable_bias, enable_relu)
