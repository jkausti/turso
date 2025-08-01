#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

typedef enum ResultCode {
  Error = -1,
  Ok = 0,
  Row = 1,
  Busy = 2,
  Io = 3,
  Interrupt = 4,
  Invalid = 5,
  Null = 6,
  NoMem = 7,
  ReadOnly = 8,
  NoData = 9,
  Done = 10,
  SyntaxErr = 11,
  ConstraintViolation = 12,
  NoSuchEntity = 13,
} ResultCode;

typedef enum ValueType {
  Integer = 0,
  Text = 1,
  Blob = 2,
  Real = 3,
  NullValue = 4,
} ValueType;

typedef union ValueUnion {
  int64_t int_val;
  double real_val;
  const char *text_ptr;
  const void *blob_ptr;
} ValueUnion;

typedef struct LimboValue {
  enum ValueType value_type;
  union ValueUnion value;
} LimboValue;

/**
 * # Safety
 * Safe to be called from Go with null terminated DSN string.
 * performs null check on the path.
 */
void *db_open(const char *path);

/**
 * Get the error value from the connection, if any, as a null
 * terminated string. The caller is responsible for freeing the
 * memory with `free_string`.
 */
const char *db_get_error(void *ctx);

/**
 * Close the database connection
 * # Safety
 * safely frees the connection's memory
 */
void db_close(void *db);

enum ResultCode rows_next(void *ctx);

const void *rows_get_value(void *ctx, uintptr_t col_idx);

void free_string(char *s);

/**
 * Function to get the number of expected ResultColumns in the prepared statement.
 * to avoid the needless complexity of returning an array of strings, this instead
 * works like rows_next/rows_get_value
 */
int32_t rows_get_columns(void *rows_ptr);

/**
 * Returns a pointer to a string with the name of the column at the given index.
 * The caller is responsible for freeing the memory, it should be copied on the Go side
 * immediately and 'free_string' called
 */
const char *rows_get_column_name(void *rows_ptr, int32_t idx);

const char *rows_get_error(void *ctx);

void rows_close(void *ctx);

void *db_prepare(void *ctx, const char *query);

enum ResultCode stmt_execute(void *ctx,
                             struct LimboValue *args_ptr,
                             uintptr_t arg_count,
                             int64_t *changes);

int32_t stmt_parameter_count(void *ctx);

void *stmt_query(void *ctx, struct LimboValue *args_ptr, uintptr_t args_count);

enum ResultCode stmt_close(void *ctx);

const char *stmt_get_error(void *ctx);

void free_blob(void *blob_ptr);
