// Minimal software-rendered libretro core used only by the test suite.
#include "libretro.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define FRAME_W 320
#define FRAME_H 240
#define STATE_SIZE 16
#define SRAM_SIZE 32

static retro_environment_t env_cb;
static retro_video_refresh_t video_cb;
static retro_audio_sample_t audio_cb;
static retro_audio_sample_batch_t audio_batch_cb;
static retro_input_poll_t input_poll_cb;
static retro_input_state_t input_state_cb;

static uint16_t framebuffer[FRAME_W * FRAME_H];
static uint8_t state[STATE_SIZE];
static uint8_t sram[SRAM_SIZE];
static unsigned frame_count;

RETRO_API unsigned retro_api_version(void) { return RETRO_API_VERSION; }

RETRO_API void retro_set_environment(retro_environment_t cb) {
  env_cb = cb;
  enum retro_pixel_format fmt = RETRO_PIXEL_FORMAT_RGB565;
  cb(RETRO_ENVIRONMENT_SET_PIXEL_FORMAT, &fmt);
  bool no_game = true;
  cb(RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME, &no_game);
}

RETRO_API void retro_set_video_refresh(retro_video_refresh_t cb) { video_cb = cb; }
RETRO_API void retro_set_audio_sample(retro_audio_sample_t cb) { audio_cb = cb; }
RETRO_API void retro_set_audio_sample_batch(retro_audio_sample_batch_t cb) { audio_batch_cb = cb; }
RETRO_API void retro_set_input_poll(retro_input_poll_t cb) { input_poll_cb = cb; }
RETRO_API void retro_set_input_state(retro_input_state_t cb) { input_state_cb = cb; }

RETRO_API void retro_init(void) { frame_count = 0; }
RETRO_API void retro_deinit(void) {}

RETRO_API void retro_get_system_info(struct retro_system_info *info) {
  memset(info, 0, sizeof(*info));
  info->library_name = "CODENAME Test Core";
  info->library_version = "1.0";
  info->valid_extensions = "bin";
  info->need_fullpath = false;
}

RETRO_API void retro_get_system_av_info(struct retro_system_av_info *info) {
  memset(info, 0, sizeof(*info));
  info->geometry.base_width = FRAME_W;
  info->geometry.base_height = FRAME_H;
  info->geometry.max_width = FRAME_W;
  info->geometry.max_height = FRAME_H;
  info->timing.fps = 60.0;
  info->timing.sample_rate = 44100.0;
}

RETRO_API bool retro_load_game(const struct retro_game_info *game) {
  (void)game;
  // Test knob: pretend to be a hardware-rendered core so the host's
  // rejection path can be exercised without a real GL/Vulkan core.
  if (getenv("TEST_CORE_REQUEST_HW") && env_cb) {
    struct retro_hw_render_callback hw;
    memset(&hw, 0, sizeof(hw));
    hw.context_type = RETRO_HW_CONTEXT_OPENGL;
    env_cb(RETRO_ENVIRONMENT_SET_HW_RENDER, &hw);
  }
  return true;
}

RETRO_API void retro_unload_game(void) {}

RETRO_API void retro_run(void) {
  if (input_poll_cb) input_poll_cb();
  frame_count++;
  for (unsigned i = 0; i < FRAME_W * FRAME_H; i++) framebuffer[i] = (uint16_t)(frame_count & 0xffff);
  sram[0] = (uint8_t)frame_count;  // lets hosts verify save-RAM snapshots change
  // Pixel 1 echoes the B button so hosts can verify input through the ABI.
  if (input_state_cb)
    framebuffer[1] = (uint16_t)input_state_cb(0, RETRO_DEVICE_JOYPAD, 0, RETRO_DEVICE_ID_JOYPAD_B);
  if (video_cb) video_cb(framebuffer, FRAME_W, FRAME_H, FRAME_W * sizeof(uint16_t));
  if (audio_batch_cb) {
    static int16_t silence[735 * 2];
    audio_batch_cb(silence, 735);
  }
}

RETRO_API size_t retro_serialize_size(void) { return STATE_SIZE; }

RETRO_API bool retro_serialize(void *data, size_t size) {
  if (size < STATE_SIZE) return false;
  memcpy(state, &frame_count, sizeof(frame_count));
  memcpy(data, state, STATE_SIZE);
  return true;
}

RETRO_API bool retro_unserialize(const void *data, size_t size) {
  if (size < STATE_SIZE) return false;
  memcpy(state, data, STATE_SIZE);
  memcpy(&frame_count, state, sizeof(frame_count));
  return true;
}

RETRO_API void *retro_get_memory_data(unsigned id) {
  return id == RETRO_MEMORY_SAVE_RAM ? sram : NULL;
}
RETRO_API size_t retro_get_memory_size(unsigned id) {
  return id == RETRO_MEMORY_SAVE_RAM ? SRAM_SIZE : 0;
}

// Unused-by-tests entry points kept for ABI completeness.
RETRO_API void retro_set_controller_port_device(unsigned port, unsigned device) {
  (void)port; (void)device;
}
RETRO_API void retro_reset(void) { frame_count = 0; }
RETRO_API unsigned retro_get_region(void) { return RETRO_REGION_NTSC; }
RETRO_API bool retro_load_game_special(unsigned type, const struct retro_game_info *info,
                                       size_t num) {
  (void)type; (void)info; (void)num;
  return false;
}
RETRO_API void retro_cheat_reset(void) {}
RETRO_API void retro_cheat_set(unsigned index, bool enabled, const char *code) {
  (void)index; (void)enabled; (void)code;
}
