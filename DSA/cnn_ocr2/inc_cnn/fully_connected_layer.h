#pragma once
// =============================================================================
//  Program : activation_function.h
//  Author  : Chang-Jyun Liao
//  Date    : July/14/2024
// -----------------------------------------------------------------------------
//  Description:
//      This file defines the fully connected layer for the CNN models.
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
//  Copyright 2024,
//                    Embedded Intelligent Systems Lab (EISL)
//                    Deparment of Computer Science
//                    National Yang Ming Chiao Tung University
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

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "activation_function.h"
#include "config.h"
#include "layer.h"
#include "list.h"
#include "util.h"

typedef struct _fully_connected_layer {
    layer_base base;

    uint8_t has_bias_;
} fully_connected_layer;

fully_connected_layer* get_fully_connected_layer_entry(struct list_node* ptr) {
    return list_entry(ptr, fully_connected_layer, base.list);
}

void fully_connected_layer_forward_propagation(struct list_node* ptr,
                                               input_struct* input) {
    fully_connected_layer* entry = get_fully_connected_layer_entry(ptr);

    if (input->in_size_ != entry->base.in_size_) {
        printf("Error input size not match %u/%u\n", input->in_size_,
               entry->base.in_size_);
        exit(-1);
    }
    float_t* in = input->in_ptr_;
    float_t* a = entry->base.a_ptr_;
    float_t* W = entry->base._W;
    float_t* b = entry->base._b;
    float_t* out = entry->base.out_ptr_;
    input->in_ptr_ = out;
    input->in_size_ = entry->base.out_size_;

    uint32_t total_size = entry->base.out_size_;

    volatile uint32_t* FC_CTRL = (uint32_t*)(0xC4000000);
    volatile float_t* FC_A_ADDR = (float_t*)(0xC4000004);  // a
    volatile float_t* FC_W_ADDR = (float_t*)(0xC4000008);  // w
    volatile uint32_t* FC_IN_ADDR = (uint32_t*)(0xC400000C);
    // in 要換掉->inner_loop_iter
    volatile float_t* FC_PW_ADDR = (float_t*)(0xC4001000);  // pw  +0-0x300

    //  in:0~192  w:entry->base.in_size_*total_size(192)    a:total_size 1
    //  b:total_size沒拆到
    // 先給 entry->base.in_size_?  (pw的週期)
    // 在這裡設定好全部的in(0~最多192)
    *FC_IN_ADDR = entry->base.in_size_;
    const float_t* inn = in;
    for (uint32_t i = 0; i < entry->base.in_size_; ++i)
        FC_PW_ADDR[i] = *inn++;  // 先放好全部的pw

    for (uint32_t i = 0; i < total_size; i++) {  // 10 30
        a[i] = (float_t)0;
        *FC_A_ADDR = a[i];
        for (uint32_t c = 0; c < entry->base.in_size_; c++) {  // 拆到這一層
            //*FC_IN_ADDR = in[c];  // 可在優化0-192           // 這些RW都是W
            *FC_W_ADDR = W[i * entry->base.in_size_ + c];

            //*FC_CTRL = 1;

            // while (*FC_CTRL == 1);  // 全部弄完大概在快0.5s
            //   當檢測到REG40=1就開始計算  好像差0.1而以不一定值得拆
            /*
            while (*FC_CTRL == 1);
            *FC_W_ADDR = W[i * entry->base.in_size_ + c];
            //in 一開始就被存起來 你輸進w他自動幫你發=1
            */
            //*FC_CTRL = 0;
        }
        a[i] = *FC_A_ADDR;
        // for (int i = 0; i < 200; ++i) *FC_CTRL = 0;

        if (entry->has_bias_)
            a[i] += b[i];
    }
    for (uint32_t i = 0; i < total_size; i++)
        out[i] = entry->base.activate(a, i, entry->base.out_size_);

#ifdef PRINT_LAYER
    printf("[%s] done [%f, %f, ... , %f, %f]\n", entry->base.layer_name_,
           out[0], out[1], out[entry->base.out_size_ - 2],
           out[entry->base.out_size_ - 1]);
#endif
}

layer_base* new_fully_connected_layer(
    cnn_controller* ctrl, float_t (*activate)(float_t*, uint32_t, uint32_t),
    uint32_t in_dim, uint32_t out_dim, uint8_t has_bias) {
    fully_connected_layer* ret =
        (fully_connected_layer*)malloc(sizeof(fully_connected_layer));

    ctrl->padding_size = 0;
    init_layer(&ret->base, ctrl, in_dim, out_dim, in_dim * out_dim,
               has_bias ? out_dim : 0, activate);
#ifdef PRINT_LAYER
    static uint32_t call_time = 0;
    sprintf(ret->base.layer_name_, "fc%u", call_time++);
#endif
    ret->has_bias_ = has_bias;
    ret->base.activate = activate;
    // printf("insize of FC layer %d\n", ret->base.in_size_);
    // printf("FC: in [%f, %f, ... , %f, %f]\n", ret->base.in_ptr_[0],
    // ret->base.in_ptr_[1], ret->base.in_ptr_[ret->base.in_size_-2],
    // ret->base.in_ptr_[ret->base.in_size_-1]);
#ifdef PRINT_LAYER
    printf("FC: W  [%f, %f, ... , %f, %f]\n", ret->base._W[0], ret->base._W[1],
           ret->base._W[in_dim * out_dim - 2],
           ret->base._W[in_dim * out_dim - 1]);
#endif
    // printf("FC: b  [%f, %f, ... , %f, %f]\n", ret->base._b[0],
    // ret->base._b[1], ret->base._b[out_dim-2], ret->base._b[out_dim-1]);
    ret->base.forward_propagation = fully_connected_layer_forward_propagation;
    return &ret->base;
}
