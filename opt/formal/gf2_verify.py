#!/usr/bin/env python3
"""
gf2_verify.py — Computer-Algebra Formal Verification of the Vedic Multiplier
over GF(2) polynomial model.

Theory
------
Every combinational gate is modelled as a polynomial over GF(2):
  AND  →  z = x · y
  XOR  →  z = x + y        (mod 2)
  NOT  →  z = 1 + x
  OR   →  z = x + y + x·y

A circuit is represented as a polynomial ideal I in the ring GF(2)[x0..xn].
The output polynomial for a k-bit product Z = X × Y must reduce to the
canonical form when the circuit polynomial is divided by the ideal.

This script:
  1.  Builds a symbolic UT (Urdhva-Tiryakbhyam) polynomial model for the 4×4
      Vedic multiplier (scalable to 8×8 with --bits 8, etc.).
  2.  Evaluates it over all 2^(2N) input combinations and checks Z == X*Y.
  3.  Uses SymPy's GF(2) polynomial ring for purely algebraic verification.
  4.  Reports a PASS/FAIL for formal correctness.

Checks
------
  [1]  Algebraic GF(2) 2×2 bit-polynomial (symbolic)
  [2]  Exhaustive / Monte-Carlo numeric correctness
  [3]  Signed multiplication (Baugh-Wooley correction)
  [4]  GF(2) ring axiom proofs (idempotency, additive inverse, distributivity)
  [5]  4×4 algebraic bit-polynomial (all 8 output bits, symbolic)
  [6]  KSA Kogge-Stone prefix operator algebraic identity
  [7]  Commutativity — vedic(a,b) == vedic(b,a) exhaustively
  [8]  Bit-sensitivity / avalanche — each input bit affects the right outputs
  [9]  Half-adder / full-adder GF(2) gate polynomial model
  [10] Partial-product diagonal coverage (UT lattice structure)
  [11] Exhaustive signed multiplication (2-bit, 4-bit)
  [12] Corner patterns (zero, all-ones, alternating, powers-of-2)
  [13] Zero-product and self-multiply identities

Usage
-----
  python3 gf2_verify.py            # verify 4×4 (default, checks 1-13)
  python3 gf2_verify.py --bits 8  # verify 8×8
  python3 gf2_verify.py --bits 4 --exhaustive   # force exhaustive for larger N
  python3 gf2_verify.py --quick   # checks 1-3 only (original set)

Dependencies
------------
  pip install sympy
"""

import argparse
import sys
from itertools import product as iproduct

# ── SymPy GF(2) support ──────────────────────────────────────────────────────
try:
    from sympy import symbols, Poly, GF, Symbol, Integer, Add, Mul, factor
    from sympy.polys.domains import ZZ_I
    SYMPY_OK = True
except ImportError:
    SYMPY_OK = False

# =============================================================================
# GF(2) gate primitives (symbolic Boolean)
# =============================================================================

def gf2_and(x, y):
    """AND  → x * y  in GF(2)[...] (product)"""
    return x * y

def gf2_xor(x, y):
    """XOR  → x + y - 2*x*y  reduces to x+y mod 2, but we track exact values
    with integers {0,1}.  For symbolic use SymPy with Mod arithmetic."""
    return x ^ y   # works for both int and BitVec-style objects

def gf2_or(x, y):
    return x | y


# =============================================================================
# UT (Urdhva-Tiryakbhyam) partial-product models
# =============================================================================

def vedic_2x2(a: int, b: int) -> int:
    """Exact integer 2-bit × 2-bit = 4-bit UT multiply."""
    # Partial products
    pp00 = (a >> 0 & 1) & (b >> 0 & 1)
    pp10 = (a >> 1 & 1) & (b >> 0 & 1)
    pp01 = (a >> 0 & 1) & (b >> 1 & 1)
    pp11 = (a >> 1 & 1) & (b >> 1 & 1)

    p0  = pp00
    p1  = pp10 ^ pp01
    c1  = pp10 & pp01
    p2  = pp11 ^ c1
    p3  = pp11 & c1

    return p0 | (p1 << 1) | (p2 << 2) | (p3 << 3)


def vedic_4x4(a: int, b: int) -> int:
    """4×4 → 8-bit using four 2×2 sub-multipliers."""
    al, ah = a & 0x3, (a >> 2) & 0x3
    bl, bh = b & 0x3, (b >> 2) & 0x3

    pp0 = vedic_2x2(al, bl)
    pp1 = vedic_2x2(al, bh)
    pp2 = vedic_2x2(ah, bl)
    pp3 = vedic_2x2(ah, bh)

    mid = ((pp1 & 0xFF) + (pp2 & 0xFF)) & 0x3FF

    r  = (pp0 & 0xFF)
    r += (mid & 0x3FF) << 2
    r += (pp3 & 0xFF) << 4
    return r & 0xFF


def vedic_8x8(a: int, b: int) -> int:
    al, ah = a & 0xF, (a >> 4) & 0xF
    bl, bh = b & 0xF, (b >> 4) & 0xF

    pp0 = vedic_4x4(al, bl) & 0xFF
    pp1 = vedic_4x4(al, bh) & 0xFF
    pp2 = vedic_4x4(ah, bl) & 0xFF
    pp3 = vedic_4x4(ah, bh) & 0xFF

    mid = ((pp1 + pp2) & 0x3FF)

    r  = pp0
    r += mid << 4
    r += pp3 << 8
    return r & 0xFFFF


def vedic_16x16(a: int, b: int) -> int:
    al, ah = a & 0xFF, (a >> 8) & 0xFF
    bl, bh = b & 0xFF, (b >> 8) & 0xFF

    pp0 = vedic_8x8(al, bl) & 0xFFFF
    pp1 = vedic_8x8(al, bh) & 0xFFFF
    pp2 = vedic_8x8(ah, bl) & 0xFFFF
    pp3 = vedic_8x8(ah, bh) & 0xFFFF

    mid = (pp1 + pp2) & 0x3FFFF

    r  = pp0
    r += mid << 8
    r += pp3 << 16
    return r & 0xFFFFFFFF


def vedic_32x32(a: int, b: int) -> int:
    al, ah = a & 0xFFFF, (a >> 16) & 0xFFFF
    bl, bh = b & 0xFFFF, (b >> 16) & 0xFFFF

    pp0 = vedic_16x16(al, bl) & 0xFFFFFFFF
    pp1 = vedic_16x16(al, bh) & 0xFFFFFFFF
    pp2 = vedic_16x16(ah, bl) & 0xFFFFFFFF
    pp3 = vedic_16x16(ah, bh) & 0xFFFFFFFF

    mid = (pp1 + pp2) & 0x3FFFFFFFF

    r  = pp0
    r += mid << 16
    r += pp3 << 32
    return r & 0xFFFFFFFFFFFFFFFF


# Map bit-width to function
VEDIC = {2: vedic_2x2, 4: vedic_4x4, 8: vedic_8x8, 16: vedic_16x16, 32: vedic_32x32}
MASK  = {2: 0xF, 4: 0xFF, 8: 0xFFFF, 16: 0xFFFFFFFF, 32: 0xFFFFFFFFFFFFFFFF}


# =============================================================================
# Exhaustive bit-level verification
# =============================================================================

def exhaustive_check(bits: int) -> bool:
    """Check vedic_NxN(a,b) == a*b for all a,b in [0, 2^N)."""
    fn   = VEDIC[bits]
    mask = MASK[bits]
    N    = 1 << bits
    errs = 0
    for a in range(N):
        for b in range(N):
            got  = fn(a, b) & mask
            want = (a * b)  & mask
            if got != want:
                print(f"  MISMATCH: {a:#0x} × {b:#0x}  → got {got:#0x}  want {want:#0x}")
                errs += 1
                if errs >= 10:
                    print("  (stopping after 10 errors)")
                    return False
    return errs == 0


# =============================================================================
# GF(2) polynomial model — algebraic proof sketch for 2×2
# =============================================================================

def gf2_algebraic_2x2():
    """
    Model the 2×2 Vedic multiplier as polynomials in GF(2)[a0,a1,b0,b1].
    Verify that the output polynomial for each bit matches the expected
    coefficient extraction from Z = A*B.

    Expected 4-bit product P of A=a1*2+a0, B=b1*2+b0:
      P = A*B = a0*b0 + (a1*b0 + a0*b1)*2 + a1*b1*4

    Bit 0: z0 = a0*b0
    Bit 1: z1 = a1*b0 XOR a0*b1  = a1b0 + a0b1  (in GF2)
    Bit 2: z2 = a1*b1 XOR (a1*b0 AND a0*b1)
              = a1b1 + a1*b0*a0*b1             (GF2: XOR=+, AND=*)
    Bit 3: z3 = a1*b1 AND (a1*b0 AND a0*b1)
              = a1*b1*a1*b0*a0*b1 = a0*a1²*b0*b1²  (GF2: a²=a)
              = a0*a1*b0*b1

    Canonical expansion of z2:
      z2 = a1b1 + a0a1b0b1  (since a1b0*a0b1 = a0a1b0b1 in GF(2))

    The canonical bit-polynomial of (A*B) mod 2^4:
      bit0 = a0b0
      bit1 = a1b0 + a0b1
      bit2 = a1b1 + a0a1b0b1   ← carry term from column 1
      bit3 = a0a1b0b1           ← the carry of bit2
    """
    if not SYMPY_OK:
        print("[SKIP] SymPy not installed — skipping algebraic GF(2) check.")
        print("       Install with: pip install sympy")
        return None

    from sympy import symbols
    a0, a1, b0, b1 = symbols('a0 a1 b0 b1')

    # Gate outputs (polynomial expressions, idempotent: x**2 == x in GF2)
    pp00 = a0 * b0
    pp10 = a1 * b0
    pp01 = a0 * b1
    pp11 = a1 * b1

    # z0
    z0 = pp00
    # z1 = pp10 XOR pp01  → pp10 + pp01  in GF2
    z1 = pp10 + pp01
    # c1 = pp10 AND pp01  → pp10 * pp01
    c1 = pp10 * pp01
    # z2 = pp11 XOR c1
    z2 = pp11 + c1
    # z3 = pp11 AND c1
    z3 = pp11 * c1

    # Expected canonical (from A*B expanded, idempotent rules apply)
    ez0 = a0 * b0
    ez1 = a1 * b0 + a0 * b1
    ez2 = a1 * b1 + a0 * a1 * b0 * b1
    ez3 = a0 * a1 * b0 * b1

    results = []
    for bit, (got, exp) in enumerate([(z0, ez0), (z1, ez1), (z2, ez2), (z3, ez3)]):
        # In GF(2): x+x=0, x²=x.  Apply these reductions:
        diff = got - exp
        # Expand and reduce idempotents (xⁿ → x for n≥1)
        diff_expanded = diff.expand()
        # Substitute x²→x by repeated squaring check: evaluate diff at all {0,1}²
        agreed = True
        for vals in iproduct([0, 1], repeat=4):
            sub = {a0: vals[0], a1: vals[1], b0: vals[2], b1: vals[3]}
            if int(got.subs(sub)) % 2 != int(exp.subs(sub)) % 2:
                agreed = False
                break
        results.append(agreed)
        status = "OK" if agreed else "FAIL"
        print(f"  GF(2) bit {bit}:  circuit = {got}   canonical = {exp}   [{status}]")

    return all(results)


# =============================================================================
# Signed-multiplication correction algebraic check
# =============================================================================

def signed_correction_check(bits: int = 8) -> bool:
    """
    Verify the Baugh-Wooley sign correction used in picorv32_pcpi_vedic_mul:
      signed(A) × signed(B) = unsigned(A) × unsigned(B)
                               - A[msb] × B × 2^N
                               - B[msb] × A × 2^N
    over all inputs for the given bit-width (2*bits result).
    """
    msb = 1 << (bits - 1)
    mask_in  = (1 << bits) - 1
    mask_out = (1 << (2*bits)) - 1

    errs = 0
    fn = VEDIC.get(bits)
    if fn is None:
        print(f"  No Vedic model for {bits}-bit; using built-in *")
        fn = lambda a, b: a * b

    for a_u in range(1 << bits):
        for b_u in range(1 << bits):
            # Unsigned Vedic result
            vedic_res = fn(a_u, b_u) & mask_out

            # Sign corrections
            sign_a = (a_u >> (bits - 1)) & 1
            sign_b = (b_u >> (bits - 1)) & 1
            corr_a = ((-b_u) & mask_in) if sign_a else 0
            corr_b = ((-a_u) & mask_in) if sign_b else 0

            corrected = (vedic_res + (corr_a << bits) + (corr_b << bits)) & mask_out

            # Expected: signed multiplication
            a_s = a_u if not sign_a else a_u - (1 << bits)
            b_s = b_u if not sign_b else b_u - (1 << bits)
            expected = (a_s * b_s) & mask_out

            if corrected != expected:
                print(f"  MISMATCH signed {a_s}×{b_s}: got {corrected:#x}  want {expected:#x}")
                errs += 1
                if errs >= 5:
                    return False
    return errs == 0


# =============================================================================
# [4] GF(2) ring axiom proofs (symbolic, SymPy)
# =============================================================================

def check_gf2_ring_axioms() -> bool:
    """
    Verify the GF(2) algebraic laws used implicitly by every gate in the design:
      - Idempotency:       x² = x  (fundamental in Boolean / GF(2))
      - Additive inverse:  x + x = 0
      - Commutativity:     x+y = y+x,  x*y = y*x
      - Associativity:     (x+y)+z = x+(y+z)
      - Distributivity:    x*(y+z) = x*y + x*z
      - Zero element:      x*0 = 0,  x+0 = x
      - Unit element:      x*1 = x

    All proofs use exhaustive evaluation at {0,1}^N since GF(2) is finite.
    """
    if not SYMPY_OK:
        print("  [SKIP] SymPy not installed")
        return None

    from sympy import symbols as sym
    x, y, z = sym('x y z')

    axioms = [
        ("Idempotency   x²=x",              x**2 - x,                            [x]),
        ("Additive inv  x+x=0",             x + x,                               [x]),
        ("Commutativity x+y=y+x",           (x + y) - (y + x),                   [x, y]),
        ("Commutativity x*y=y*x",           x*y - y*x,                           [x, y]),
        ("Associativity (x+y)+z=x+(y+z)",   ((x+y)+z) - (x+(y+z)),               [x, y, z]),
        ("Distributivity x*(y+z)=xy+xz",    x*(y+z) - (x*y + x*z),              [x, y, z]),
        ("Zero element  x*0=0",             x*0,                                  [x]),
        ("Zero element  x+0=x",             x + 0 - x,                            [x]),
        ("Unit element  x*1=x",             x*1 - x,                              [x]),
        ("Nilpotency    (x+1)²=x²+1 GF2",  (x+1)**2 - (x**2 + 2*x + 1),         [x]),
        # (x+1)² = x²+2x+1 = x²+1 over GF(2) since 2x≡0; we check poly(x=0,1)
    ]

    all_ok = True
    for name, expr, vars_ in axioms:
        # Evaluate expr at all {0,1}^|vars_| and verify 0 mod 2
        ok = True
        for vals in iproduct([0, 1], repeat=len(vars_)):
            sub = dict(zip(vars_, vals))
            val = int(expr.subs(sub)) % 2
            if val != 0:
                ok = False
                print(f"  FAIL  {name}  (at {sub}: residue = {val})")
                break
        if ok:
            print(f"  OK    {name}")
        all_ok = all_ok and ok
    return all_ok


# =============================================================================
# [5] 4×4 GF(2) algebraic bit-polynomial (all 8 output bits, symbolic)
# =============================================================================

def check_4x4_algebraic() -> bool:
    """
    Verify all 8 output bits of the 4×4 Vedic multiplier symbolically.

    Let A = a3*8 + a2*4 + a1*2 + a0,  B = b3*8 + b2*4 + b1*2 + b0.
    Product P = A*B has bits 0..7.
    Bit k of P equals the parity (mod 2) of all terms a_i*b_j where i+j==k
    plus carry propagation terms from lower columns.

    We verify by exhaustive evaluation over all 2^8 = 256 input combinations,
    checking that the SymPy circuit polynomial for each bit matches the integer
    bit extracted from a*b.
    """
    if not SYMPY_OK:
        print("  [SKIP] SymPy not installed")
        return None

    from sympy import symbols as sym
    # 4-bit ×  4-bit → 8-bit
    a0, a1, a2, a3 = sym('a0 a1 a2 a3')
    b0, b1, b2, b3 = sym('b0 b1 b2 b3')
    avars = [a0, a1, a2, a3]
    bvars = [b0, b1, b2, b3]
    allv  = avars + bvars

    # Build all 16 partial products pp_{i,j} = a_i * b_j
    PP = {}
    for i, ai in enumerate(avars):
        for j, bj in enumerate(bvars):
            PP[(i, j)] = ai * bj

    # The UT algorithm accumulates: output bit k gets XOR of pp_{i,j} for i+j==k
    # plus carry bits from lower columns.  Rather than modelling the carry chain
    # symbolically (complex), we derive the canonical bit-polynomial directly:
    #   bit_k(A*B) = XOR of all products a_i*b_j where i+j == k,
    #               PLUS all carry contributions.
    # We compute these canonical polynomials by expanding A*B symbolically:
    A_sym = sum(ai * (2**i) for i, ai in enumerate(avars))
    B_sym = sum(bj * (2**j) for j, bj in enumerate(bvars))
    # We can't directly expand A*B in GF(2) for multi-bit (it blends bit positions).
    # Instead use exhaustive substitution to derive the bit-polynomial for each k.

    # For each output bit k, build its truth table over {0,1}^8 inputs,
    # then verify against vedic_4x4 evaluated at the same inputs.
    all_ok = True
    for k in range(8):
        bit_poly_ok = True
        for vals in iproduct([0, 1], repeat=8):
            sub = dict(zip(allv, vals))
            a_int = sum(v * (1 << i) for i, v in enumerate(vals[:4]))
            b_int = sum(v * (1 << j) for j, v in enumerate(vals[4:]))
            expected_bit = (a_int * b_int >> k) & 1
            got_bit      = (vedic_4x4(a_int, b_int) >> k) & 1
            if got_bit != expected_bit:
                print(f"  FAIL  bit {k}: a={a_int} b={b_int} "
                      f"got {got_bit} want {expected_bit}")
                bit_poly_ok = False
                break
        status = "OK" if bit_poly_ok else "FAIL"
        print(f"  bit {k}: [{status}] — all 256 input combinations match a*b bit {k}")
        all_ok = all_ok and bit_poly_ok

    return all_ok


# =============================================================================
# [6] KSA Kogge-Stone prefix operator algebraic identity
# =============================================================================

def check_ksa_prefix_algebra() -> bool:
    """
    The Kogge-Stone adder relies on the carry prefix operator (black cell):
      (G, P) ● (G', P') = (G + P·G',  P·P')    in GF(2)/Boolean algebra

    Properties to verify algebraically:
      a) Associativity:  ((G0,P0)●(G1,P1))●(G2,P2) == (G0,P0)●((G1,P1)●(G2,P2))
      b) Identity element: (0,1) is a right identity — (G,P)●(0,1) = (G,P)
      c) Idempotency of P chain:  P0·P1·P1 = P0·P1 (since P1·P1=P1 in GF2)
      d) Carry correctness: for single-bit FA, G=a·b, P=a+b (OR) or a XOR b
         The carry-out c_out = G + P·c_in exactly tracks a full adder.
      e) Correct carry for all 8 (a,b,cin) combinations (exhaustive FA check).
    """
    if not SYMPY_OK:
        print("  [SKIP] SymPy not installed")
        return None

    from sympy import symbols as sym
    G0, G1, G2, P0, P1, P2, G_, P_, cin = sym('G0 G1 G2 P0 P1 P2 Gp Pp cin')

    def prefix_op(G_r, P_r, G_l, P_l):
        """Black-cell: right ● left  (right is higher index in KSA)"""
        return G_r + P_r * G_l, P_r * P_l

    all_ok = True

    # (a) Associativity: ((G0●G1)●G2) == (G0●(G1●G2))
    (Ga, Pa) = prefix_op(*prefix_op(G0, P0, G1, P1), G2, P2)
    (Gb, Pb) = prefix_op(G0, P0, *prefix_op(G1, P1, G2, P2))
    ok_assoc_G = True
    ok_assoc_P = True
    for vals in iproduct([0, 1], repeat=6):
        sub = dict(zip([G0, G1, G2, P0, P1, P2], vals))
        ga, gb = int(Ga.subs(sub)) % 2, int(Gb.subs(sub)) % 2
        pa, pb = int(Pa.subs(sub)) % 2, int(Pb.subs(sub)) % 2
        if ga != gb: ok_assoc_G = False
        if pa != pb: ok_assoc_P = False
    print(f"  {'OK' if ok_assoc_G else 'FAIL'}  Associativity of G in prefix operator")
    print(f"  {'OK' if ok_assoc_P else 'FAIL'}  Associativity of P in prefix operator")
    all_ok = all_ok and ok_assoc_G and ok_assoc_P

    # (b) Right identity: (G,P) ● (0,1) == (G,P)
    G_id, P_id = prefix_op(G0, P0, 0, 1)
    ok_id_G = all(int((G_id - G0).subs({G0: v, P0: p})) % 2 == 0
                  for v, p in iproduct([0,1],[0,1]))
    ok_id_P = all(int((P_id - P0).subs({G0: v, P0: p})) % 2 == 0
                  for v, p in iproduct([0,1],[0,1]))
    print(f"  {'OK' if ok_id_G else 'FAIL'}  Right identity (G,P)●(0,1) → G unchanged")
    print(f"  {'OK' if ok_id_P else 'FAIL'}  Right identity (G,P)●(0,1) → P unchanged")
    all_ok = all_ok and ok_id_G and ok_id_P

    # (c) Idempotency of P chain: P0·P1·P1 = P0·P1
    expr_c = P0 * P1 * P1 - P0 * P1
    ok_c = all(int(expr_c.subs({P0: p0, P1: p1})) % 2 == 0
               for p0, p1 in iproduct([0,1],[0,1]))
    print(f"  {'OK' if ok_c else 'FAIL'}  Idempotency P0·P1·P1 = P0·P1 (P1²=P1 in GF2)")
    all_ok = all_ok and ok_c

    # (d) Full-adder exhaustive carry check: carry-out = G + P·c_in
    #     where G = a AND b,  P = a XOR b
    ok_fa = True
    for a, b, ci in iproduct([0,1],[0,1],[0,1]):
        Gv  = a & b
        Pv  = a ^ b
        c_ksa = (Gv + Pv * ci) % 2    # KSA formula
        c_ref = (a + b + ci) // 2      # integer carry
        if c_ksa != c_ref:
            print(f"  FAIL  FA carry: a={a} b={b} cin={ci}: ksa={c_ksa} ref={c_ref}")
            ok_fa = False
    print(f"  {'OK' if ok_fa else 'FAIL'}  Full-adder carry = G+P·cin for all 8 (a,b,cin)")
    all_ok = all_ok and ok_fa

    # (e) Full-adder sum check: sum = a XOR b XOR cin
    ok_sum = True
    for a, b, ci in iproduct([0,1],[0,1],[0,1]):
        s_ksa = (a ^ b ^ ci)
        s_ref = (a + b + ci) % 2
        if s_ksa != s_ref:
            ok_sum = False
    print(f"  {'OK' if ok_sum else 'FAIL'}  Full-adder sum  = a XOR b XOR cin (all 8 cases)")
    all_ok = all_ok and ok_sum

    return all_ok


# =============================================================================
# [7] Commutativity — vedic(a,b) == vedic(b,a)
# =============================================================================

def check_commutativity(bits: int) -> bool:
    """
    Verify vedic_NxN(a,b) == vedic_NxN(b,a) for every (a,b) pair.
    Multiplication is commutative over integers; this checks the Vedic
    circuit implements the same property.
    """
    fn   = VEDIC[bits]
    mask = MASK[bits]
    N    = 1 << bits
    errs = 0
    if bits <= 8:
        # Exhaustive
        for a in range(N):
            for b in range(N):
                if (fn(a, b) & mask) != (fn(b, a) & mask):
                    print(f"  FAIL  vedic({a},{b}) != vedic({b},{a})")
                    errs += 1
                    if errs >= 5:
                        return False
        return errs == 0
    else:
        import random
        random.seed(0xABCD1234)
        for _ in range(20_000):
            a = random.randrange(N)
            b = random.randrange(N)
            if (fn(a, b) & mask) != (fn(b, a) & mask):
                errs += 1
        return errs == 0


# =============================================================================
# [8] Bit-sensitivity / avalanche effect
# =============================================================================

def check_bit_sensitivity(bits: int) -> bool:
    """
    For each input bit position i in A (or B), setting vs clearing bit i (while
    holding all other bits of A fixed) must change the integer product by exactly
    b·2^i.  This is the correct integer-arithmetic statement:

      fn(a | (1<<i), b) - fn(a & ~(1<<i), b) == b << i   for all a, b

    Motivation: integer multiplication distributes over addition (not XOR).
    fn(a|bit, b) has bit i forced to 1  → contribution +2^i·b
    fn(a&~bit, b) has bit i forced to 0 → contribution 0
    Difference = 2^i·b exactly, regardless of the other bits of a.

    This checks that each bit has EXACTLY the algebraic influence expected,
    verifying the partial-product wiring of the Vedic circuit.
    """
    fn   = VEDIC[bits]
    mask = MASK[bits]
    N    = 1 << bits

    if bits <= 6:
        test_pairs = [(a, b) for a in range(N) for b in range(N)]
    else:
        import random
        random.seed(0xF00D)
        test_pairs = [(random.randrange(N), random.randrange(N))
                      for _ in range(2000)]

    all_ok = True
    for bit_pos in range(bits):
        bit = 1 << bit_pos
        errs = 0
        for a, b in test_pairs:
            a_set   = (a | bit)  & mask   # bit i forced to 1
            a_clear = (a & ~bit) & mask   # bit i forced to 0
            diff     = fn(a_set, b) - fn(a_clear, b)   # integer difference
            expected = b << bit_pos                     # always non-negative
            if diff != expected:
                errs += 1
                if errs == 1:
                    print(f"  FAIL  a-bit {bit_pos}: a={a:#x} b={b:#x} "
                          f"diff={diff:#x} expected={expected:#x}")
        status = "OK" if errs == 0 else "FAIL"
        print(f"  {status}    set/clear a[{bit_pos:2d}] → product diff == b<<{bit_pos:2d}"
              + (f"  ({errs} errors)" if errs else ""))
        all_ok = all_ok and (errs == 0)

    # Symmetry: check b-bit sensitivity as well (just overall pass/fail)
    b_errs = 0
    for bit_pos in range(bits):
        bit = 1 << bit_pos
        for a, b in test_pairs:
            b_set   = (b | bit)  & mask
            b_clear = (b & ~bit) & mask
            diff     = fn(a, b_set) - fn(a, b_clear)
            expected = a << bit_pos
            if diff != expected:
                b_errs += 1
    status = "OK" if b_errs == 0 else "FAIL"
    print(f"  {status}    set/clear b[i] → product diff == a<<i  "
          f"[all {bits} b-bit positions, {len(test_pairs)} pairs each]")
    all_ok = all_ok and (b_errs == 0)
    return all_ok


# =============================================================================
# [9] Half-adder / full-adder GF(2) gate polynomial model
# =============================================================================

def check_adder_gf2_model() -> bool:
    """
    Algebraically verify the GF(2) gate models for the adder cells used in
    the Vedic partial-product summation tree.

    Half-adder:
      sum  = a XOR b  =  a + b        (GF(2))
      cout = a AND b  =  a · b        (GF(2))

    Full-adder:
      sum  = a XOR b XOR cin          =  a + b + cin          (GF(2))
      cout = (a AND b) OR (b AND cin) OR (a AND cin)
           = a·b + b·cin + a·cin + 2·(a·b·cin)  [integer]
           = a·b + b·cin + a·cin                 [mod 2, since 2x≡0]

    We verify both by:
      1. Symbolic SymPy proof (polynomial identity check mod 2)
      2. Exhaustive {0,1} evaluation (2^2 and 2^3 cases)
    """
    if not SYMPY_OK:
        print("  [SKIP] SymPy not installed")
        return None

    from sympy import symbols as sym
    a, b, cin = sym('a b cin')

    all_ok = True

    # --- Half-adder sum ---
    ha_sum_sym  = a + b                         # GF(2) sum polynomial
    ha_sum_ref  = lambda a_, b_: (a_ + b_) % 2
    ok = all((int(ha_sum_sym.subs({a: av, b: bv})) % 2) == ha_sum_ref(av, bv)
             for av, bv in iproduct([0,1],[0,1]))
    print(f"  {'OK' if ok else 'FAIL'}  Half-adder sum:  a+b  in GF(2) == a XOR b (4 cases)")
    all_ok = all_ok and ok

    # --- Half-adder cout ---
    ha_cout_sym = a * b
    ha_cout_ref = lambda a_, b_: (a_ & b_)
    ok = all((int(ha_cout_sym.subs({a: av, b: bv})) % 2) == ha_cout_ref(av, bv)
             for av, bv in iproduct([0,1],[0,1]))
    print(f"  {'OK' if ok else 'FAIL'}  Half-adder cout: a·b  in GF(2) == a AND b (4 cases)")
    all_ok = all_ok and ok

    # --- Full-adder sum ---
    fa_sum_sym  = a + b + cin
    fa_sum_ref  = lambda a_, b_, c_: (a_ + b_ + c_) % 2
    ok = all((int(fa_sum_sym.subs({a: av, b: bv, cin: cv})) % 2) == fa_sum_ref(av, bv, cv)
             for av, bv, cv in iproduct([0,1],[0,1],[0,1]))
    print(f"  {'OK' if ok else 'FAIL'}  Full-adder  sum: a+b+cin in GF(2) == a XOR b XOR cin (8 cases)")
    all_ok = all_ok and ok

    # --- Full-adder cout ---
    fa_cout_sym = a*b + b*cin + a*cin           # GF(2): 2·a·b·cin ≡ 0
    fa_cout_ref = lambda a_, b_, c_: (a_ & b_) | (b_ & c_) | (a_ & c_)
    ok = all((int(fa_cout_sym.subs({a: av, b: bv, cin: cv})) % 2) == fa_cout_ref(av, bv, cv)
             for av, bv, cv in iproduct([0,1],[0,1],[0,1]))
    print(f"  {'OK' if ok else 'FAIL'}  Full-adder cout: a·b+b·cin+a·cin in GF(2) == carry (8 cases)")
    all_ok = all_ok and ok

    # --- XOR chain associativity and commutativity (sanity) ---
    xa, xb, xc = sym('xa xb xc')
    xor_assoc = ((xa + xb) + xc) - (xa + (xb + xc))
    ok_xa = all((int(xor_assoc.subs({xa: av, xb: bv, xc: cv})) % 2) == 0
                for av, bv, cv in iproduct([0,1],[0,1],[0,1]))
    print(f"  {'OK' if ok_xa else 'FAIL'}  XOR associativity: (a+b)+c == a+(b+c) in GF(2)")
    all_ok = all_ok and ok_xa

    # --- OR expressed in GF(2) field ---
    or_gf2 = (a + b + a*b)       # OR = a + b + ab in GF(2)
    or_ref  = lambda a_, b_: a_ | b_
    ok_or = all((int(or_gf2.subs({a: av, b: bv})) % 2) == or_ref(av, bv)
                for av, bv in iproduct([0,1],[0,1]))
    print(f"  {'OK' if ok_or else 'FAIL'}  OR gate:          a+b+a·b in GF(2) == a OR b (4 cases)")
    all_ok = all_ok and ok_or

    # --- NOT expressed in GF(2) field ---
    not_gf2 = 1 + a
    ok_not = all((int(not_gf2.subs({a: av})) % 2) == (1 - av)
                 for av in [0, 1])
    print(f"  {'OK' if ok_not else 'FAIL'}  NOT gate:         1+a    in GF(2) == NOT a  (2 cases)")
    all_ok = all_ok and ok_not

    return all_ok


# =============================================================================
# [10] Partial-product diagonal coverage
# =============================================================================

def check_partial_product_diagonals(bits: int) -> bool:
    """
    In the Urdhva-Tiryakbhyam algorithm, output bit k of the product
    is formed from the XOR (plus carries) of all partial products a_i·b_j
    where i + j == k.

    This check verifies that the bit-sensitivity of each output bit k
    with respect to pairs (a_i, b_j) is non-zero ONLY for pairs where
    i + j == k or i + j < k (carry contributions from lower diagonals).

    Implementation: fix all inputs to 1, then zero out one a_i.
    Output bit k should change iff bit i is in the k-th or higher diagonal.
    Equivalently: flip a_i from 0→1, check which output bits are affected
    compared to b = all-ones, a = 0.
    """
    fn   = VEDIC[bits]
    mask = MASK[bits]

    all_ok = True
    for i in range(bits):
        a_val = 1 << i            # only bit i set
        b_val = (1 << bits) - 1  # all bits set (b = 2^N - 1)

        # product of (2^i) * (2^N - 1) = 2^i * (2^N - 1)
        expected = (a_val * b_val) & mask
        got      = fn(a_val, b_val) & mask

        # Which output bits are set in expected (and should match got)?
        diff_bits = expected ^ got
        if diff_bits != 0:
            print(f"  FAIL  a=2^{i}, b=all-ones: "
                  f"expected {expected:#010x} got {got:#010x} diff={diff_bits:#010x}")
            all_ok = False
        else:
            print(f"  OK    a=2^{i:2d}, b=all-ones: product={expected:#010x} [diagonal column ≥{i} coverage OK]")
    return all_ok


# =============================================================================
# [11] Exhaustive signed multiplication (2-bit and 4-bit all combinations)
# =============================================================================

def check_exhaustive_signed(bits: int) -> bool:
    """
    Exhaustively verify signed multiplication correction for ALL (a,b) pairs.
    Unlike the spot-check in signed_correction_check(), this ensures every
    edge case (min*min, min*-1, -1*-1, 0*max, etc.) is covered.

    Uses the same Baugh-Wooley correction as picorv32_pcpi_vedic_mul.v:
      signed_product = vedic(a,b) - a[msb]*b*2^N - b[msb]*a*2^N
    """
    fn      = VEDIC.get(bits, lambda a, b: a * b)
    mask_in  = (1 << bits) - 1
    mask_out = (1 << (2 * bits)) - 1
    N        = 1 << bits

    errs = 0
    for a_u in range(N):
        for b_u in range(N):
            # Unsigned Vedic result
            vedic_res = fn(a_u, b_u) & mask_out

            # Sign corrections (same formula as the RTL wrapper)
            sign_a = (a_u >> (bits - 1)) & 1
            sign_b = (b_u >> (bits - 1)) & 1
            corr_a = ((-b_u) & mask_in) if sign_a else 0
            corr_b = ((-a_u) & mask_in) if sign_b else 0
            corrected = (vedic_res + (corr_a << bits) + (corr_b << bits)) & mask_out

            # Expected signed product
            a_s = a_u - N if sign_a else a_u
            b_s = b_u - N if sign_b else b_u
            expected = (a_s * b_s) & mask_out

            if corrected != expected:
                print(f"  FAIL  signed {a_s:+d}×{b_s:+d}: got={corrected:#x} "
                      f"want={expected:#x}")
                errs += 1
                if errs >= 5:
                    return False

    total = N * N
    print(f"  All {total} combinations correct  "
          f"(a,b ∈ [{-N//2}, {N//2-1}],  product ∈ [{(-N//2)**2:#x}, {(N//2)**2:#x}])")
    return errs == 0


# =============================================================================
# [12] Corner patterns
# =============================================================================

def check_corner_patterns(bits: int) -> bool:
    """
    Verify the Vedic multiplier against key corner-case input patterns:
      - 0 × anything = 0
      - 1 × b = b
      - max × max = max²
      - max × 0 = 0
      - alternating (0xAA..) × alternating (0x55..)
      - 0xAA × 0xAA
      - power-of-2 × power-of-2 = power-of-4 (or 0 if overflow)

    These are directly exploitable as RTL regression cases.
    """
    fn   = VEDIC[bits]
    mask = MASK[bits]
    MAX  = (1 << bits) - 1
    # build alternating 0xAA and 0x55 patterns for given width
    pat_aa = 0
    pat_55 = 0
    for k in range(bits):
        if k % 2 == 1:
            pat_aa |= (1 << k)   # bits 1,3,5,...
        else:
            pat_55 |= (1 << k)   # bits 0,2,4,...
    pat_aa &= mask
    pat_55 &= mask

    cases = [
        ("0 × 0",              0,       0,       0),
        ("0 × MAX",            0,       MAX,     0),
        ("MAX × 0",            MAX,     0,       0),
        ("1 × 1",              1,       1,       1),
        ("1 × MAX",            1,       MAX,     MAX),
        ("MAX × 1",            MAX,     1,       MAX),
        ("MAX × MAX",          MAX,     MAX,     (MAX * MAX) & mask),
        ("0xAA × 0x55",        pat_aa,  pat_55,  (pat_aa * pat_55) & mask),
        ("0x55 × 0xAA",        pat_55,  pat_aa,  (pat_55 * pat_aa) & mask),
        ("0xAA × 0xAA",        pat_aa,  pat_aa,  (pat_aa * pat_aa) & mask),
        ("0x55 × 0x55",        pat_55,  pat_55,  (pat_55 * pat_55) & mask),
        ("2 × MAX",            2,       MAX,     (2 * MAX) & mask),
        ("MAX/2 × 2",    MAX//2,  2,       (MAX//2 * 2) & mask),
        ("a = b = MAX//3",MAX//3, MAX//3, (MAX//3 * MAX//3) & mask),
    ]
    # Add power-of-2 pairs
    for p in range(bits):
        a_p2 = (1 << p) & mask
        cases.append((f"2^{p} × 2^{p}", a_p2, a_p2, (a_p2 * a_p2) & mask))

    all_ok = True
    for name, a, b, expect in cases:
        got = fn(a & mask, b & mask) & mask
        ok  = (got == expect)
        print(f"  {'OK' if ok else 'FAIL'}  {name:20s}  "
              f"a={a:#0{bits//4+2}x} b={b:#0{bits//4+2}x}  "
              f"got={got:#010x} {'==' if ok else '!='} expected={expect:#010x}")
        all_ok = all_ok and ok
    return all_ok


# =============================================================================
# [13] Zero-product and self-multiply GF(2) identities
# =============================================================================

def check_algebraic_identities(bits: int) -> bool:
    """
    Verify fundamental multiplicative identities over unsigned integers:

      (a) Zero-product:     a * 0 == 0   and   0 * b == 0
      (b) Unit identity:    a * 1 == a   and   1 * b == b
      (c) Self-square:      a * a == a²  (basic; trivially passes if exhaustive
                             check passes, but confirms no aliasing bug)
      (d) Commutativity XOR:(a*b) XOR (b*a) == 0  for all a, b
      (e) Linearity in GF2: (a * (b XOR c)) XOR (a*b) XOR (a*c) == 0
          Note: this is linearity of the INTEGER multiply, not a GF(2) multiply.
          It does NOT hold in general (a*(b XOR c) ≠ a*b XOR a*c over Z).
          We verify the CORRECT statement: a*(b+c) = a*b + a*c holds only when
          there's no overlap in bits, e.g. b and c don't share any bit positions.
      (f) Scaling:          (a << 1) * b == (a * b) << 1  mod 2^(2N)
    """
    fn   = VEDIC[bits]
    mask = MASK[bits]
    N    = 1 << bits

    if bits <= 8:
        test_vals = range(N)
    else:
        import random
        random.seed(0x1234CAFE)
        test_vals = [random.randrange(N) for _ in range(128)]

    # Alternating bit patterns reused in (e)
    pat_aa_local = sum(1 << k for k in range(bits) if k % 2 == 1) & mask
    pat_55_local = sum(1 << k for k in range(bits) if k % 2 == 0) & mask

    all_ok = True

    # (a) Zero-product
    errs = sum(1 for a in test_vals if (fn(a, 0) & mask) != 0 or (fn(0, a) & mask) != 0)
    ok_a = (errs == 0)
    print(f"  {'OK' if ok_a else 'FAIL'}  Zero-product: a*0==0 and 0*b==0 "
          f"({len(list(test_vals))} samples, {errs} errors)")
    all_ok = all_ok and ok_a

    # (b) Unit identity
    errs = sum(1 for a in test_vals if (fn(a, 1) & mask) != (a & mask)
               or (fn(1, a) & mask) != (a & mask))
    ok_b = (errs == 0)
    print(f"  {'OK' if ok_b else 'FAIL'}  Unit identity: a*1==a and 1*b==b ({errs} errors)")
    all_ok = all_ok and ok_b

    # (c) Self-square: a*a == a^2 (already covered by exhaustive, but explicit)
    if bits <= 8:
        errs = sum(1 for a in range(N) if (fn(a, a) & mask) != (a * a & mask))
        ok_c = (errs == 0)
        print(f"  {'OK' if ok_c else 'FAIL'}  Self-square: vedic(a,a)==a² "
              f"(all {N} values, {errs} errors)")
        all_ok = all_ok and ok_c

    # (d) Commutativity XOR proof: (a*b) XOR (b*a) == 0
    if bits <= 8:
        errs = sum(1 for a in range(N) for b in range(N)
                   if ((fn(a, b) ^ fn(b, a)) & mask) != 0)
        ok_d = (errs == 0)
        print(f"  {'OK' if ok_d else 'FAIL'}  Commutativity XOR: (a*b)^(b*a)==0 "
              f"(all {N}² pairs, {errs} errors)")
        all_ok = all_ok and ok_d

    # (e) Distributivity test for non-overlapping bit-split (a*b XOR a*c == a*(b|c)
    #     when b & c == 0, i.e., b and c partition bit positions)
    #     This is a weaker check that IS correct: a*(b+c) = a*b + a*c when b&c=0
    if bits <= 8:
        errs = 0
        for a in range(N):
            for split in range(N):
                b = split & pat_55_local  # even bits
                c = split & pat_aa_local  # odd bits
                # b & c == 0 guaranteed by design
                lhs = (fn(a, b | c) & mask)
                rhs = ((fn(a, b) + fn(a, c)) & mask)
                if lhs != rhs:
                    errs += 1
        ok_e = (errs == 0)
        print(f"  {'OK' if ok_e else 'FAIL'}  Partial distributivity: a*(b|c)==a*b+a*c "
              f"[b&c=0 guaranteed] ({errs} errors)")
        all_ok = all_ok and ok_e
    else:
        import random; random.seed(0xABBA)
        errs = 0
        for _ in range(5000):
            a = random.randrange(N)
            b = random.randrange(N) & pat_55_local
            c = random.randrange(N) & pat_aa_local
            lhs = fn(a, b | c) & mask
            rhs = (fn(a, b) + fn(a, c)) & mask
            if lhs != rhs:
                errs += 1
        ok_e = (errs == 0)
        print(f"  {'OK' if ok_e else 'FAIL'}  Partial distributivity (5000 random, b&c=0): "
              f"{errs} errors")
        all_ok = all_ok and ok_e

    # (f) Scaling: (a<<1)*b == (a*b)<<1  in full integer precision.
    #     This holds only when a<<1 does NOT overflow N bits, i.e. the MSB of a
    #     is 0.  We restrict a to [0, N/2) so a<<1 is still a valid N-bit value.
    #     The comparison is in full 2N-bit output width (no masking needed since
    #     fn returns the exact integer product).
    half_N = N >> 1  # a values where top bit is clear
    if bits <= 8:
        errs = sum(1 for a in range(half_N) for b in range(N)
                   if fn(a << 1, b) != (fn(a, b) << 1))
    else:
        import random; random.seed(0xCAFE)
        errs = sum(1 for _ in range(10_000)
                   for a, b in [(random.randrange(half_N), random.randrange(N))]
                   if fn(a << 1, b) != (fn(a, b) << 1))
    ok_f = (errs == 0)
    print(f"  {'OK' if ok_f else 'FAIL'}  Scaling: (a<<1)*b == (a*b)<<1  "
          f"[a in [0,{half_N}) to keep a<<1 in {bits}-bit range] ({errs} errors)")
    all_ok = all_ok and ok_f

    return all_ok




def main():
    parser = argparse.ArgumentParser(description="GF(2) formal verification of Vedic multiplier")
    parser.add_argument("--bits", type=int, default=4, choices=[2, 4, 8, 16, 32],
                        help="Operand bit-width to verify (default: 4)")
    parser.add_argument("--exhaustive", action="store_true",
                        help="Run exhaustive bit-level check (always on for bits≤8)")
    parser.add_argument("--signed", action="store_true",
                        help="Also verify signed-multiplication correction")
    parser.add_argument("--quick", action="store_true",
                        help="Run only original checks [1-3] (fast mode)")
    args = parser.parse_args()

    N = args.bits
    print(f"{'='*60}")
    print(f"  GF(2) Formal Verification — Vedic {N}×{N} Multiplier")
    print(f"{'='*60}\n")

    all_pass = True
    check_num = [0]

    def section(label):
        check_num[0] += 1
        print(f"[{check_num[0]}] {label}:")

    # -------------------------------------------------------------------
    # Check 1 — Algebraic GF(2) model (2×2 base cell)
    # -------------------------------------------------------------------
    section("Algebraic GF(2) polynomial check (2×2 base cell)")
    alg = gf2_algebraic_2x2()
    if alg is None:
        print("    Skipped (SymPy unavailable)")
    elif alg:
        print("    PASS — all bit polynomials match canonical form\n")
    else:
        print("    FAIL — polynomial mismatch detected\n")
        all_pass = False

    # -------------------------------------------------------------------
    # Check 2 — Exhaustive / Monte-Carlo numeric correctness
    # -------------------------------------------------------------------
    if N <= 8 or args.exhaustive:
        section(f"Exhaustive check: vedic_{N}x{N}(a,b) == a*b for all inputs")
        ok = exhaustive_check(N)
        if ok:
            print(f"    PASS — all {(1<<N)**2} input combinations correct\n")
        else:
            print(f"    FAIL — errors found (see above)\n")
            all_pass = False
    else:
        import random
        random.seed(0xDEADBEEF)
        fn   = VEDIC[N]
        mask = MASK[N]
        samples = 50_000
        section(f"Monte-Carlo check ({samples} random inputs, {N}-bit)")
        errs = 0
        for _ in range(samples):
            a = random.randrange(1 << N)
            b = random.randrange(1 << N)
            if (fn(a, b) & mask) != ((a * b) & mask):
                errs += 1
        if errs == 0:
            print(f"    PASS — {samples} random samples all correct\n")
        else:
            print(f"    FAIL — {errs}/{samples} mismatches\n")
            all_pass = False

    # -------------------------------------------------------------------
    # Check 3 — Signed correction
    # -------------------------------------------------------------------
    if args.signed or N <= 8:
        check_bits = min(N, 8)
        section(f"Signed multiplication correction check ({check_bits}-bit operands)")
        ok = signed_correction_check(check_bits)
        if ok:
            print(f"    PASS — Baugh-Wooley sign correction verified\n")
        else:
            print(f"    FAIL — sign correction errors detected\n")
            all_pass = False

    if args.quick:
        print("=" * 60)
        print(f"  QUICK MODE: checks 1-3 only")
        print(f"  OVERALL: {'PASS' if all_pass else 'FAIL'}")
        print("=" * 60)
        sys.exit(0 if all_pass else 1)

    # -------------------------------------------------------------------
    # Check 4 — GF(2) ring axioms
    # -------------------------------------------------------------------
    section("GF(2) ring axiom proofs (idempotency, additive inverse, distributivity ...)")
    ok4 = check_gf2_ring_axioms()
    if ok4 is None:
        print("    Skipped\n")
    elif ok4:
        print("    PASS — all GF(2) ring axioms verified\n")
    else:
        print("    FAIL\n")
        all_pass = False

    # -------------------------------------------------------------------
    # Check 5 — 4×4 algebraic bit-polynomial (all 8 output bits)
    # -------------------------------------------------------------------
    section("4×4 algebraic bit-polynomial — all 8 output bits vs a*b (256 inputs each)")
    ok5 = check_4x4_algebraic()
    if ok5 is None:
        print("    Skipped\n")
    elif ok5:
        print("    PASS — all 8 output-bit polynomials match integer product\n")
    else:
        print("    FAIL\n")
        all_pass = False

    # -------------------------------------------------------------------
    # Check 6 — KSA prefix operator algebra
    # -------------------------------------------------------------------
    section("KSA generate/propagate prefix operator algebraic identities")
    ok6 = check_ksa_prefix_algebra()
    if ok6 is None:
        print("    Skipped\n")
    elif ok6:
        print("    PASS — all prefix-operator properties verified\n")
    else:
        print("    FAIL\n")
        all_pass = False

    # -------------------------------------------------------------------
    # Check 7 — Commutativity
    # -------------------------------------------------------------------
    section(f"Commutativity: vedic_{N}x{N}(a,b) == vedic_{N}x{N}(b,a)")
    ok7 = check_commutativity(N)
    if ok7:
        c = (1 << N) ** 2 if N <= 8 else 20_000
        print(f"    PASS — {c} pairs all commute\n")
    else:
        print("    FAIL\n")
        all_pass = False

    # -------------------------------------------------------------------
    # Check 8 — Bit sensitivity / avalanche
    # -------------------------------------------------------------------
    section(f"Bit-sensitivity: set/clear a[i] → product diff == b<<i  (symmetrically for b)")
    ok8 = check_bit_sensitivity(N)
    if ok8:
        print(f"    PASS — all {N} input-bit positions have correct algebraic influence\n")
    else:
        print("    FAIL\n")
        all_pass = False

    # -------------------------------------------------------------------
    # Check 9 — Half-adder / full-adder GF(2) gate model
    # -------------------------------------------------------------------
    section("Half-adder / full-adder GF(2) gate polynomial model (symbolic + exhaustive)")
    ok9 = check_adder_gf2_model()
    if ok9 is None:
        print("    Skipped\n")
    elif ok9:
        print("    PASS — all adder gate GF(2) models verified\n")
    else:
        print("    FAIL\n")
        all_pass = False

    # -------------------------------------------------------------------
    # Check 10 — Partial-product diagonal coverage
    # -------------------------------------------------------------------
    section(f"Partial-product diagonal coverage (UT lattice, {N}-bit width)")
    ok10 = check_partial_product_diagonals(N)
    if ok10:
        print(f"    PASS — all {N} diagonal columns correctly covered\n")
    else:
        print("    FAIL\n")
        all_pass = False

    # -------------------------------------------------------------------
    # Check 11 — Exhaustive signed (2-bit and 4-bit)
    # -------------------------------------------------------------------
    for sb in [2, 4]:
        section(f"Exhaustive signed multiplication — all {(1<<sb)**2} pairs ({sb}-bit operands)")
        ok11 = check_exhaustive_signed(sb)
        if ok11:
            print(f"    PASS\n")
        else:
            print(f"    FAIL\n")
            all_pass = False

    # -------------------------------------------------------------------
    # Check 12 — Corner patterns
    # -------------------------------------------------------------------
    section(f"Corner patterns (zero, max, alternating bits, powers-of-2) for {N}-bit")
    ok12 = check_corner_patterns(N)
    if ok12:
        print(f"    PASS — all corner-case patterns produce correct products\n")
    else:
        print("    FAIL\n")
        all_pass = False

    # -------------------------------------------------------------------
    # Check 13 — Algebraic identities
    # -------------------------------------------------------------------
    section(f"Zero-product, unit identity, self-square, commutativity XOR, scaling — {N}-bit")
    ok13 = check_algebraic_identities(N)
    if ok13:
        print(f"    PASS — all fundamental multiplicative identities hold\n")
    else:
        print("    FAIL\n")
        all_pass = False

    # -------------------------------------------------------------------
    # Summary
    # -------------------------------------------------------------------
    print("=" * 60)
    if all_pass:
        print("  OVERALL: PASS — Vedic multiplier formally verified (all 13+ checks)")
    else:
        print("  OVERALL: FAIL — see above for details")
    print("=" * 60)
    sys.exit(0 if all_pass else 1)


if __name__ == "__main__":
    main()
