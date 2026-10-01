// placeholder — Script/build_llama.sh 首次运行时会用 llama.cpp 官方头文件覆盖本目录
#ifndef LOCALCODERIDE_LLAMA_H
#define LOCALCODERIDE_LLAMA_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

typedef struct llama_model    llama_model;
typedef struct llama_context  llama_context;
typedef struct llama_sampler  llama_sampler;

typedef int32_t llama_token;

// 占位 batch 布局 —— llama_batch 必须完整可见才能让 Swift 导入；
// 真实 llama.h 会覆盖这里，但字段顺序对 llama.cpp v4000+ 是兼容的。
typedef struct llama_batch {
    int32_t n_tokens;
    void   *token;
    void   *embd;
    void   *pos;
    void   *seq_id;
    void   *logits;
    int32_t n_seq_max;
    size_t  embd_ddim;
} llama_batch;

typedef struct llama_model_params {
    int     n_gpu_layers;
    int     main_gpu;
    bool    use_mlock;
    bool    use_mmap;
    bool    low_vram;
    bool    vocab_only;
} llama_model_params;

typedef struct llama_context_params {
    uint32_t n_ctx;
    uint32_t n_batch;
    uint32_t n_threads;
} llama_context_params;

typedef struct llama_sampler_chain_params_t {
    uint32_t seed;
    float    top_p;
    uint32_t top_k;
    float    temp;
    float    repeat_penalty;
} llama_sampler_chain_params_t;

struct llama_chat_message {
    const char *role;
    const char *content;
};

void llama_backend_init(void);
void llama_backend_free(void);
bool llama_backend_load_from_file(const char *name, void *params);

llama_model_params   llama_model_default_params(void);
llama_context_params llama_context_default_params(void);

llama_model *llama_model_load_from_file(const char *fname, llama_model_params params);
void    llama_model_free(llama_model *model);
uint32_t llama_model_n_ctx_train(const llama_model *model);
uint32_t llama_model_n_layer(const llama_model *model);
void llama_model_desc(const llama_model *model, char *buf, size_t buf_size);

llama_context *llama_new_context_with_model(llama_model *model, llama_context_params params);
void           llama_free(llama_context *ctx);

// llama_tokenize 返回成功时为 token 数，失败为负
int32_t llama_tokenize(const llama_model *model, const char *text, int32_t text_len,
                       int32_t *tokens, int32_t *n_tokens,
                       bool add_special, bool parse_special);
int32_t llama_token_eos(const llama_model *model);
int32_t llama_token_nl(const llama_model *model);

void llama_kv_cache_clear(llama_context *ctx);
void llama_kv_cache_seq_add(llama_context *ctx, int32_t seq_id, int32_t delta, int32_t start);

llama_batch llama_batch_init(uint32_t n_tokens, size_t embd, int32_t n_seq_max);
void llama_batch_free(llama_batch *batch);
void llama_batch_clear(llama_batch *batch);
void llama_batch_add(llama_batch *batch, int32_t id, uint32_t pos,
                     const int32_t *seq_ids, bool logits);

// llama_decode 成功 0，失败非 0
int32_t llama_decode(llama_context *ctx, llama_batch batch);

// llama_detokenize 返回写入字节数，<=0 失败
int32_t llama_detokenize(const llama_model *model, const int32_t *tokens, int32_t n_tokens,
                         char *text, int32_t text_len_max, bool remove_special, bool unparse_special);

bool llama_chat_apply_template(const llama_model *model, const char *tmpl_name,
                                const struct llama_chat_message *chat,
                                int32_t n_msg, bool add_assistant,
                                char *out, int32_t out_len, int32_t *written);

llama_sampler_chain_params_t llama_sampler_chain_default_params(void);
llama_sampler *llama_sampler_chain_init(llama_sampler_chain_params_t params);
void           llama_sampler_chain_add(llama_sampler *chain, llama_sampler *sampler);
void           llama_sampler_free(llama_sampler *sampler);
llama_sampler *llama_sampler_init_top_k(uint32_t k);
llama_sampler *llama_sampler_init_top_p(float p, uint32_t seed);
llama_sampler *llama_sampler_init_temp(float t);
llama_sampler *llama_sampler_init_dist(uint32_t seed);
int32_t        llama_sampler_sample(llama_sampler *chain, llama_context *ctx, int32_t idx);
void           llama_sampler_accept(llama_sampler *chain, int32_t token);

#ifdef __cplusplus
}
#endif

#endif
