// =============================================================================
//  Program : rtos_mmul.c
//  Author  : DeepSeek, with slight modifications by Chun-Jen Tsai
//  Date    : Sep/4/2025
// -----------------------------------------------------------------------------
//  Description:
//  This is a multi-thread program for FreeRTOS.
//
//  This program is designed as one of the homework project for the course:
//  Microprocessor Systems: Principles and Implementation
//  Dept. of CS, NYCU (aka NCTU), Hsinchu, Taiwan.
// -----------------------------------------------------------------------------
//  Revision information:
//
//  None.
// =============================================================================

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "FreeRTOS.h"
#include "semphr.h"
#include "task.h"

#define N 128             // Size of matrices.
#define NUM_TASKS 4       // Number of tasks (threads).
#define STACK_DEPTH 1024  // Stack size of each task.

// Shared task parameter structure.
typedef struct {
    float* A;
    float* B;
    float* C;
    int n;
    int start_row;
    int end_row;
    SemaphoreHandle_t completion_sem;
} matrix_task_params_t;

// Global pointers to matrix data.
float* matrix_A;
float* matrix_B;
float* matrix_C;

// Matrix Initialization
void init_matrix(float* matrix, int n) {
    for (int i = 0; i < n * n; i++) {
        matrix[i] = (float)rand() / RAND_MAX;
    }
}

// A sub-matrix multiplication task
void matrix_multiply_task(void* pvParameters) {
    matrix_task_params_t* params = (matrix_task_params_t*)pvParameters;
    int n = params->n;

    taskENTER_CRITICAL();
    printf("Column %d to %d multiplication task begins...\n", params->start_row,
           params->end_row - 1);
    taskEXIT_CRITICAL();

    for (int i = params->start_row; i < params->end_row; i++) {
        for (int j = 0; j < n; j++) {
            float sum = 0.0;
            for (int k = 0; k < n; k++) {
                sum += params->A[i * n + k] * params->B[k * n + j];
            }
            params->C[i * n + j] = sum;
        }

        // For normal programs, we should relinquish CPU to
        // other tasks periodically. But here, we try to stretch
        // the capability of a preemptive multitasking kernel.
        // So, we try to make each task as greedy as possible.
#if 1
        if (i % 10 == 0) {
            taskYIELD();
        }
#endif

#if 0  // Set to '1' to show current running task.
    taskENTER_CRITICAL();
    printf("%s\n", pcTaskGetName(NULL));
    taskEXIT_CRITICAL();
#endif
    }

    taskENTER_CRITICAL();
    printf("Column %d to %d multiplication task finished.\n", params->start_row,
           params->end_row - 1);
    taskEXIT_CRITICAL();

    // Post the completion of a task.
    xSemaphoreGive(params->completion_sem);

    vTaskDelete(NULL);
}

// Creation of multiplication sub-tasks
void create_matrix_tasks(void) {
    SemaphoreHandle_t completion_sem = xSemaphoreCreateCounting(NUM_TASKS, 0);
    matrix_task_params_t task_params[NUM_TASKS];

    int rows_per_task = N / NUM_TASKS;
    int extra_rows = N % NUM_TASKS;
    int current_row = 0;

    // Create 'NUM_TASKS' tasks in a loop.
    for (int i = 0; i < NUM_TASKS; i++) {
        task_params[i].A = matrix_A;
        task_params[i].B = matrix_B;
        task_params[i].C = matrix_C;
        task_params[i].n = N;
        task_params[i].completion_sem = completion_sem;
        task_params[i].start_row = current_row;

        int rows = rows_per_task + (i < extra_rows ? 1 : 0);
        task_params[i].end_row = current_row + rows;
        current_row = task_params[i].end_row;

        // We cannot use snprintf() to create the task name here
        // because there is a linking bug in GCC in multi-library
        // environment.
        char task_name[16] = "Task 0";
        task_name[5] += i;

        if (xTaskCreate(matrix_multiply_task, task_name, STACK_DEPTH,
                        &task_params[i], tskIDLE_PRIORITY + 1,
                        NULL) != pdPASS) {
            taskENTER_CRITICAL();
            printf("Error: cannot create task %d\n", i);
            taskEXIT_CRITICAL();
        }
    }

    // Waiting for all tasks to complete.
    for (int i = 0; i < NUM_TASKS; i++) {
        xSemaphoreTake(completion_sem, portMAX_DELAY);
    }

    vSemaphoreDelete(completion_sem);
    taskENTER_CRITICAL();
    printf("All tasks are completed!\n");
    taskEXIT_CRITICAL();
}

// Main task.
void main_task(void* pvParameters) {
    TickType_t start_time, end_time;

    printf("FreeRTOS Parallel Matrix Multiplication\n");
    printf("Matrix size: %d x %d\n", N, N);
    printf("Number of tasks: %d\n", NUM_TASKS);

    // Initialization of the matrices
    matrix_A = (float*)pvPortMalloc(N * N * sizeof(float));
    matrix_B = (float*)pvPortMalloc(N * N * sizeof(float));
    matrix_C = (float*)pvPortMalloc(N * N * sizeof(float));
    srand(12345);
    init_matrix(matrix_A, N);
    init_matrix(matrix_B, N);
    memset(matrix_C, 0, N * N * sizeof(float));

    printf("Matrices initialization completed.\n");

    // Recording start time
    start_time = xTaskGetTickCount();

    // Creating all computing tasks
    create_matrix_tasks();

    // Recording end time
    end_time = xTaskGetTickCount();

    printf("Computation done! Time spent: %lu ticks.\n",
           (unsigned long)(end_time - start_time));

    // End program
    printf("Program finished.\n");
    vPortFree(matrix_A);
    vPortFree(matrix_B);
    vPortFree(matrix_C);

    // Enter the forever-sleep loop
    for (;;) {
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}

// Main entry point of the program
int main(void) {
    // Create the main task
    if (xTaskCreate(main_task, "MainTask", STACK_DEPTH * 2, NULL,
                    tskIDLE_PRIORITY + 2, NULL) != pdPASS) {
        printf("Error：cannot not create the main task!\n");
        return 1;
    }

    // Activate all tasks
    vTaskStartScheduler();

    // When you hit this point, that means something is wrong
    printf("Error：FreeRTOS scheduler quits!\n");
    return 1;
}

// FreeRTOS Hooks.
void vApplicationStackOverflowHook(TaskHandle_t xTask, char* pcTaskName) {
    printf("Stack overflow! Task: %s!\n", pcTaskName);
    for (;;);
}

void vApplicationMallocFailedHook(void) {
    printf("Memory allocation failed!\n");
    for (;;);
}

void vApplicationIdleHook(void) {
    /* No useful task is running, do something stupid here */
}

void vApplicationTickHook(void) { /* vApplicationTickHook */ }

void vExternalISR(uint32_t cause) {}
