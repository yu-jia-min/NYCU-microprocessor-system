// =============================================================================
//  Program : string.c
//  Author  : Chun-Jen Tsai
//  Date    : Dec/09/2019
// -----------------------------------------------------------------------------
//  Description:
//  This is the minimal string library for aquila.
// -----------------------------------------------------------------------------
//  Revision information:
//
//  None.
// -----------------------------------------------------------------------------
//  License information:
//
//  This software is released under the BSD-3-Clause Licence,
//  see https://opensource.org/licenses/BSD-3-Clause for details.
//  In the following license statements, "software" refers to the
//  "source code" of the complete hardware/software system.
//
//  Copyright 2019,
//                    Embedded Intelligent Systems Lab (EISL)
//                    Deparment of Computer Science
//                    National Chiao Tung Uniersity
//                    Hsinchu, Taiwan.
//
//  All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:
//
//  1. Redistributions of source code must retain the above copyright notice,
//     this list of conditions and the following disclaimer.
//
//  2. Redistributions in binary form must reproduce the above copyright notice,
//     this list of conditions and the following disclaimer in the documentation
//     and/or other materials provided with the distribution.
//
//  3. Neither the name of the copyright holder nor the names of its
//  contributors
//     may be used to endorse or promote products derived from this software
//     without specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
//  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
//  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
//  ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
//  LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
//  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
//  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
//  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
//  CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
//  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
//  POSSIBILITY OF SUCH DAMAGE.
// =============================================================================
#include <stdio.h>
#include <string.h>

void *memcpy(void *d, void *s, size_t n) {
    unsigned char *dst = (unsigned char *)d;
    unsigned char *src = (unsigned char *)s;

    for (int idx = 0; idx < n; idx++) *(dst++) = *(src++);
    return d;
}

void *memmove(void *d, void *s, size_t n) {
    unsigned char *dst = (unsigned char *)d;
    unsigned char *src = (unsigned char *)s;

    if ((unsigned)d >= (unsigned)s && (unsigned)d <= (unsigned)s + n) {
        for (int idx = n - 1; idx >= 0; idx--) dst[idx] = src[idx];
    } else {
        for (int idx = 0; idx < n; idx++) *(dst++) = *(src++);
    }

    return d;
}

void *memset(void *d, int v, size_t n) {
    unsigned char *dst = (unsigned char *)d;

    for (int idx = 0; idx < n; idx++) *(dst++) = (unsigned char)v;
    return d;
}

long strlen(char *s) {
    long n = 0;

    while (*s++) n++;
    return n;
}

typedef unsigned int u32;

char *strcpy(char *dst, char *src) {
    char *ret = dst;

    // 指標轉成 word 指標
    u32 *wdst = (u32 *)dst;
    const u32 *wsrc = (const u32 *)src;

    while (1) {
        u32 w = *wsrc++;

        // 檢查 word 裡有沒有 '\0'
        if (((w - 0x01010101) & ~w & 0x80808080) != 0) {
            // 有 '\0'，代表這是最後一個 word，要逐 byte 複製
            const char *csrc = (const char *)(wsrc - 1);
            char *cdst = (char *)wdst;
            while ((*cdst++ = *csrc++));
            break;
        }

        *wdst++ = w;
    }

    return ret;
}

char *strncpy(char *dst, char *src, size_t n) {
    char *tmp = dst;

    while (*src && n) *(tmp++) = *(src++), n--;
    while (n--) *(tmp++) = 0;
    return dst;
}

char *strcat(char *dst, char *src) {
    char *tmp = dst;

    while (*tmp) tmp++;
    while (*src) *(tmp++) = *(src++);
    *tmp = 0;
    return dst;
}

char *strncat(char *dst, char *src, size_t n) {
    char *tmp = dst;

    while (*tmp) tmp++;
    while (*src && n) *(tmp++) = *(src++), n--;
    *tmp = 0;
    return dst;
}

int strcmp(char *s1, char *s2) {
    const unsigned char *p1 = (const unsigned char *)s1;
    const unsigned char *p2 = (const unsigned char *)s2;

    // 讓兩端對齊餘數一致（同餘），避免未對齊就進入快路徑
    unsigned long am = sizeof(unsigned long) - 1UL;
    while ((((unsigned long)p1) & am) != (((unsigned long)p2) & am)) {
        unsigned char a = *p1++, b = *p2++;
        if (a != b)
            return (a < b) ? -1 : 1;
        if (a == 0)
            return 0;
    }
    // 推到 word 邊界（此時兩端餘數已相同）
    while ((((unsigned long)p1) & am) != 0UL) {
        unsigned char a = *p1++, b = *p2++;
        if (a != b)
            return (a < b) ? -1 : 1;
        if (a == 0)
            return 0;
    }

    const unsigned long *w1 = (const unsigned long *)p1;
    const unsigned long *w2 = (const unsigned long *)p2;

    for (;;) {
        // 8×展開：一次比較 8 個 word（降低分支密度）
        for (int i = 0; i < 8; i++) {
            unsigned long a = w1[i];
            unsigned long b = w2[i];
            unsigned long diff = a ^ b;

            // 零位元檢測（依平台 32/64 位元自動常量折疊）
            unsigned long z1, z2;
            if (sizeof(unsigned long) == 8) {
                z1 = ((a - 0x0101010101010101UL) & ~a & 0x8080808080808080UL);
                z2 = ((b - 0x0101010101010101UL) & ~b & 0x8080808080808080UL);
            } else {  // 假設 32-bit unsigned long
                z1 = ((a - 0x01010101UL) & ~a & 0x80808080UL);
                z2 = ((b - 0x01010101UL) & ~b & 0x80808080UL);
            }

            // 有差異或含 '\0' → 回到逐位元組決勝（很快結束）
            if ((diff | z1 | z2) != 0UL) {
                p1 = (const unsigned char *)(w1 + i);
                p2 = (const unsigned char *)(w2 + i);
                for (;;) {
                    unsigned char c1 = *p1++, c2 = *p2++;
                    if (c1 != c2)
                        return (c1 < c2) ? -1 : 1;  // unsigned 比較
                    if (c1 == 0)
                        return 0;
                }
            }
        }
        w1 += 8;
        w2 += 8;
    }
}

int strncmp(char *s1, char *s2, size_t n) {
    int value;

    s1--, s2--;
    do {
        s1++, s2++;
        if (*s1 == *s2) {
            value = 0;
        } else if (*s1 < *s2) {
            value = -1;
            break;
        } else {
            value = 1;
            break;
        }
    } while (--n && *s1 != 0 && *s2 != 0);
    return value;
}
