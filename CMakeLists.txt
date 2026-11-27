cmake_minimum_required(VERSION 3.24)

project(veyra VERSION 2.2.1 LANGUAGES C CXX)

# The Windows runtime needs the resource compiler; Linux does not have one.
if(WIN32)
  enable_language(RC)
endif()
# Shown in the EXE's version resource and in the package name. CMake versions
# must be numeric, so the beta marker lives here instead.
set(VEYRA_DISPLAY_VERSION "${PROJECT_VERSION}" CACHE STRING "Human-readable version string")
# The cache keeps the first value it ever saw, so a release that bumps
# project(VERSION) used to ship an EXE still stamped with the previous display
# string. Re-align it whenever the cached label does not start with the project
# version; an explicit matching label (e.g. "1.4.0beta") is still honoured.
if(NOT VEYRA_DISPLAY_VERSION MATCHES "^${PROJECT_VERSION}")
  message(STATUS "VEYRA_DISPLAY_VERSION ${VEYRA_DISPLAY_VERSION} does not match project ${PROJECT_VERSION}; using ${PROJECT_VERSION}")
  set(VEYRA_DISPLAY_VERSION "${PROJECT_VERSION}" CACHE STRING "Human-readable version string" FORCE)
endif()

if(NOT WIN32)
  message(FATAL_ERROR "This app builds on Windows only")
endif()
add_subdirectory(src/virtualcam)

# Decode the localized compiler output using the current console code page.
# CMake needs UTF-8 internally to write rules.ninja; the generator then emits
# the matching native prefix so Ninja records header dependencies.
if(MSVC AND CMAKE_GENERATOR MATCHES "Ninja")
  set(VEYRA_INCLUDE_PROBE "${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/veyra-include-probe")
  file(WRITE "${VEYRA_INCLUDE_PROBE}.h" "// Dependency parser probe\n")
  file(WRITE "${VEYRA_INCLUDE_PROBE}.cpp" "#include \"veyra-include-probe.h\"\n")
  execute_process(COMMAND "${CMAKE_CXX_COMPILER}" /nologo /utf-8 /showIncludes /c /TP "${VEYRA_INCLUDE_PROBE}.cpp" "/Fo${VEYRA_INCLUDE_PROBE}.obj"
    OUTPUT_VARIABLE VEYRA_INCLUDE_OUTPUT ERROR_VARIABLE VEYRA_INCLUDE_OUTPUT
    RESULT_VARIABLE VEYRA_INCLUDE_RESULT ENCODING AUTO)
  if(NOT VEYRA_INCLUDE_RESULT EQUAL 0 OR NOT VEYRA_INCLUDE_OUTPUT MATCHES "(^|[\r\n])([^\r\n]*: )[ ]*[A-Za-z]:[^\r\n]*veyra-include-probe.h")
    message(FATAL_ERROR "Unable to verify MSVC/Ninja header dependency prefix")
  endif()
  set(CMAKE_CL_SHOWINCLUDES_PREFIX "${CMAKE_MATCH_2}")
endif()

# ---------------------------------------------------------------------------
# Veyra cache variables and feature switches (Playbook section 5.1).
# Machine-specific absolute paths are resolved by scripts/build.ps1 at
# configure time; CMakePresets.json stays free of local paths.
# ---------------------------------------------------------------------------
set(VEYRA_DLSS_SDK_ROOT "" CACHE PATH "NVIDIA DLSS SDK root")
set(VEYRA_NVOF_SDK_ROOT "" CACHE PATH "NVIDIA Optical Flow SDK root")
if(NOT VEYRA_NVOF_SDK_ROOT)
  set(VEYRA_NVOF_CANDIDATE "${CMAKE_CURRENT_SOURCE_DIR}/third_party_local/nvidia/Optical_Flow_SDK_5.0.7")
  if(EXISTS "${VEYRA_NVOF_CANDIDATE}/NvOFInterface/nvOpticalFlowCommon.h")
    set(VEYRA_NVOF_SDK_ROOT "${VEYRA_NVOF_CANDIDATE}")
  endif()
endif()
set(VEYRA_RUNTIME_ROOT "" CACHE PATH "Local NVIDIA runtime root")
set(VEYRA_FFMPEG_ROOT "" CACHE PATH "vcpkg-installed x64-windows root with FFmpeg (player deps)")
option(VEYRA_ENABLE_DEINTERLACE "Enable optional LGPL FFmpeg deinterlacing module" ON)
set(VEYRA_CLIP_TOOLS_ROOT "" CACHE PATH "vcpkg-installed x64-windows root with openh264-enabled FFmpeg (clip tooling only)")

option(VEYRA_ENABLE_EXPERIMENTAL_DLSSNR
  "Enable local-only experimental Feature 18 adapter" OFF)
option(VEYRA_ENABLE_DLSS_SR "Enable public DLSS SR backend" OFF)
option(VEYRA_ENABLE_DLSS_FG "Enable public DLSSG backend" OFF)
option(VEYRA_ENABLE_NVOF "Enable NVIDIA Optical Flow guidance" OFF)
option(VEYRA_ENABLE_D3D12_DEBUG "Enable D3D12 debug layer" ON)
set(VEYRA_FIDELITYFX_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/third_party_local/amd/FidelityFX-SDK/sdk" CACHE PATH "Local official FidelityFX SDK 1.1.4")
set(VEYRA_XESS_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/third_party_local/intel/xess-3.0.2" CACHE PATH "Local Intel XeSS SDK 3.0.2")
set(VEYRA_FIDELITYFX2_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/third_party_local/amd/FidelityFX-SDK-2.3.0/Kits/FidelityFX" CACHE PATH "Local AMD FidelityFX SDK 2.3.0 Kits/FidelityFX tree")

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(VeyraWarnings)
include(VeyraShaders)

# NVIDIA's static NGX core shim (nvsdk_ngx_s*.lib) is built against the
# static CRT (MT/MTd); match it for the diagnostic tools that link it.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

# ---------------------------------------------------------------------------
# Targets grow phase by phase; only what actually compiles is declared.
# ---------------------------------------------------------------------------
add_library(veyra_base STATIC
  src/base/Log.cpp
  src/base/PrivateFrameTrace.cpp
  src/base/NgxResult.cpp
  src/base/FileIdentity.cpp
  src/base/InstanceWindow.cpp
  src/base/RuntimePaths.cpp
  src/base/ThunkHook.cpp
  # .cube parsing, the runtime LUT store and named colour looks: low level, no
  # D3D12, shared by the ingest pipeline and the settings/import paths.
  src/engine/ColorLut.cpp
  src/engine/ColorLookStore.cpp
)
veyra_apply_warnings(veyra_base)
target_compile_options(veyra_base PUBLIC /utf-8)
target_compile_features(veyra_base PUBLIC cxx_std_20)
target_compile_definitions(veyra_base PUBLIC
  UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
target_include_directories(veyra_base PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_link_libraries(veyra_base PUBLIC bcrypt wintrust crypt32 version)

# On-screen text reading for live translation (OCR passes, cleanup, line timing),
# with a scripted OCR engine: no GPU, no Windows OCR language needed.

# When each on-screen line's translation is shown (src/ui/CaptionPresenter.h, no Qt).

add_library(veyra_gfx STATIC
  src/gfx/GpuSchedulingPriority.cpp
  src/gfx/NvidiaVrrProfile.cpp
  src/gfx/D3D12DeviceContext.cpp
  src/gfx/CommandSlotRing.cpp
  src/gfx/PresentSink.cpp
  src/gfx/XessPresenter.cpp
  src/gfx/XessMfgUnlock.cpp
  src/gfx/XessPacing.cpp
  src/gfx/FsrFgPresenter.cpp
  src/gfx/AmfFrcBackend.cpp
  src/gfx/RifeDmlBackend.cpp
  src/gfx/AmfVideoSrBackend.cpp
  src/gfx/FsrSrBackend.cpp
)
veyra_apply_warnings(veyra_gfx)
target_compile_features(veyra_gfx PUBLIC cxx_std_20)
target_link_libraries(veyra_gfx PUBLIC veyra_base d3d12 dxgi dxguid)

# Isolated driver-profile policy/ABI tests: no NGX, media source or graphics device.
if(EXISTS "${VEYRA_XESS_ROOT}/inc/xess_fg/xefg_swapchain_d3d12.h")
  target_include_directories(veyra_gfx PRIVATE "${VEYRA_XESS_ROOT}/inc")
  target_compile_definitions(veyra_gfx PRIVATE VEYRA_HAS_XESS=1)
endif()
# AMD AMF SDK headers (MIT) for AMD FRC; the runtime comes with the AMD driver.
set(VEYRA_AMF_SDK_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/third_party_local/amd/AMF-SDK-1.5.3" CACHE PATH "AMD AMF SDK (include/core, include/components)")
if(EXISTS "${VEYRA_AMF_SDK_ROOT}/include/components/FRC.h")
  target_include_directories(veyra_gfx PRIVATE "${VEYRA_AMF_SDK_ROOT}/include")
  target_compile_definitions(veyra_gfx PRIVATE VEYRA_HAS_AMF=1)
  if(EXISTS "${VEYRA_AMF_SDK_ROOT}/include/components/HQScaler.h")
    target_compile_definitions(veyra_gfx PRIVATE VEYRA_HAS_AMF_HQ_SCALER=1)
  endif()
  target_link_libraries(veyra_gfx PRIVATE ole32)
else()
  message(STATUS "AMF SDK headers not found at ${VEYRA_AMF_SDK_ROOT}; AMD FRC is unavailable in this build")
endif()
# RIFE frame generation: ONNX Runtime (MIT) and DirectML headers only; the
# runtime DLLs and models are loaded from runtime/rife at run time.
set(VEYRA_ORT_DML_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/deps/ort-dml" CACHE PATH "ONNX Runtime DirectML NuGet (ort/build/native/include) and DirectML NuGet (dml/include)")
if(EXISTS "${VEYRA_ORT_DML_ROOT}/ort/build/native/include/dml_provider_factory.h" AND EXISTS "${VEYRA_ORT_DML_ROOT}/dml/include/DirectML.h")
  target_include_directories(veyra_gfx PRIVATE "${VEYRA_ORT_DML_ROOT}/ort/build/native/include" "${VEYRA_ORT_DML_ROOT}/dml/include")
  target_compile_definitions(veyra_gfx PRIVATE VEYRA_HAS_RIFE_DML=1)
else()
  message(STATUS "ONNX Runtime DirectML headers not found at ${VEYRA_ORT_DML_ROOT}; RIFE is unavailable in this build")
endif()
if(EXISTS "${VEYRA_FIDELITYFX2_ROOT}/framegeneration/include/dx12/ffx_api_framegeneration_dx12.h")
  target_include_directories(veyra_gfx PRIVATE
    "${VEYRA_FIDELITYFX2_ROOT}/api/include"
    "${VEYRA_FIDELITYFX2_ROOT}/framegeneration/include"
    "${VEYRA_FIDELITYFX2_ROOT}/upscalers/include")
  target_compile_definitions(veyra_gfx PRIVATE VEYRA_HAS_FSR=1)
endif()
if(VEYRA_ENABLE_D3D12_DEBUG)
  target_compile_definitions(veyra_gfx PUBLIC VEYRA_D3D12_DEBUG=1)
endif()

# ---------------------------------------------------------------------------
# veyra_ngx: NGX core host + local experimental DLSSNR adapter.
# Compiled only with the explicit experimental switch; missing SDK paths are
# a configure-time failure, never a runtime surprise (Playbook 5.1/8.1).
# ---------------------------------------------------------------------------
if(VEYRA_ENABLE_EXPERIMENTAL_DLSSNR)
  if(NOT VEYRA_DLSS_SDK_ROOT OR NOT EXISTS "${VEYRA_DLSS_SDK_ROOT}/include/nvsdk_ngx.h")
    message(FATAL_ERROR "VEYRA_ENABLE_EXPERIMENTAL_DLSSNR requires VEYRA_DLSS_SDK_ROOT pointing at NVIDIA DLSS SDK 310.7 (include/nvsdk_ngx.h missing)")
  endif()
add_library(veyra_ngx STATIC
  src/ngx/NgxCoreHost.cpp
  src/ngx/NgxCoreCache.cpp
  src/ngx/DlssNrRuntimeAdapter.cpp
  src/ngx/NvapiLifetime.cpp
  src/ngx/DlssSrBackend.cpp
    src/ngx/VideoSrBackend.cpp
    src/ngx/TrueHdrBackend.cpp
  src/ngx/AnrProvider.cpp
  src/ngx/DlssFgBackend.cpp
  src/ngx/FgCompatibilitySession.cpp
  src/ngx/compat/hde/hde64.c
  src/ngx/AdaMfgUnlock.cpp
  src/ngx/AmpereMfgUnlock.cpp
  src/ngx/MfgUnlockUtil.cpp
  src/ngx/NvapiArchSpoof.cpp
  src/ngx/DlssgTransfusion.cpp
)
  set_source_files_properties(src/ngx/compat/hde/hde64.c PROPERTIES LANGUAGE CXX)
  veyra_apply_warnings(veyra_ngx)
  target_compile_features(veyra_ngx PUBLIC cxx_std_20)
  target_link_libraries(veyra_ngx PUBLIC veyra_base veyra_gfx d3d11)
  target_include_directories(veyra_ngx PUBLIC
    "${VEYRA_DLSS_SDK_ROOT}/include")
  # NVIDIA ships the static core shim as MT-Release; the _dbg variants match
  # the MDd debug runtime. Pick per configuration to avoid LNK2038.
  target_link_libraries(veyra_ngx PRIVATE
    "$<IF:$<CONFIG:Debug>,${VEYRA_DLSS_SDK_ROOT}/lib/Windows_x86_64/x64/nvsdk_ngx_s_dbg.lib,${VEYRA_DLSS_SDK_ROOT}/lib/Windows_x86_64/x64/nvsdk_ngx_s.lib>")
  target_compile_definitions(veyra_ngx PUBLIC
    VEYRA_EXPERIMENTAL_LOCAL_DLSSNR=1 VEYRA_HAS_NGX_CORE_CACHE=1 VEYRA_HAS_PAUSED_NR_RESIDUAL_REUSE=1)

  # Diagnostic: exercises the Ada multi-frame unlock against the local DLSS-G
  # runtime image without involving NGX (works on any NVIDIA adapter).

  # Diagnostic: exercises the RTX 30 (sm_86) Ampere unlock against the local
  # DLSS-G runtime image without involving NGX (works on any NVIDIA adapter).
endif()

# Dolby/DTS endpoint passthrough capability probe (diagnostic, never shipped).

# Isolated descriptor/Present diagnosis probe (user directive 2026-09-04 s3).
# No NGX/FFmpeg/NVOF/WASAPI. Uses PresentBlit shaders for cases F/G.

# Presentation scaler check (2026-11-18): drives PresentBlit offscreen and
# compares the fine path with a CPU model, the old bilinear blit and a
# Lanczos-3 reference, and times each blit. D3D12 only.

veyra_add_compute_shader(veyra_shader_parity_encode ParityEncode)
veyra_add_compute_shader(veyra_shader_parity_decode ParityDecode)
veyra_add_compute_shader(veyra_shader_rdna3_nr_decode Rdna3NrDecode)
veyra_add_compute_shader(veyra_shader_hdr_video_sr HdrVideoSrRestore)
veyra_add_compute_shader(veyra_shader_sr_resolve SrResolve)
veyra_add_compute_shader(veyra_shader_hdr_amd_nr_encode HdrAmdNrEncode)
veyra_add_compute_shader(veyra_shader_hdr_amd_nr_restore HdrAmdNrRestore)
if(VEYRA_ENABLE_EXPERIMENTAL_DLSSNR)
  veyra_add_compute_shader(veyra_shader_test_pattern GenerateTestPattern)

  # NR stacking probe: several Feature-18 handles on one snippet session.

  # Phase 6: DLSSG truth harness + WASAPI audio probe.
endif()

# YUV→RGB shader is shared between the media pipeline and the harness.
veyra_add_compute_shader(veyra_shader_yuv_to_rgb YuvToLinearRgb)
veyra_add_compute_shader(veyra_shader_rgb_to_linear RgbToLinear)
veyra_add_compute_shader(veyra_shader_color_grade ColorGradePass)
# 纹理 / 清晰度 / 去朦胧: block statistics, blur, apply (ColorDetailPass).
veyra_add_compute_shader(veyra_shader_color_detail_reduce ColorDetailReduce)
veyra_add_compute_shader(veyra_shader_color_detail_blur ColorDetailBlur)
veyra_add_compute_shader(veyra_shader_color_detail_apply ColorDetailApply)
veyra_add_compute_shader(veyra_shader_yuy2_to_linear Yuy2ToLinear)
veyra_add_compute_shader(veyra_shader_packed_capture PackedCaptureToLinear)
add_dependencies(veyra_shader_rgb_to_linear veyra_shader_yuy2_to_linear)
# ScaleBlit: working frame -> swapchain backbuffer (Phase 6 present path).
veyra_add_compute_shader(veyra_shader_scale_blit ScaleBlit)
veyra_add_nis_shaders(veyra_shader_nis)

veyra_add_compute_shader(veyra_shader_effect_exclusion EffectExclusion)
# Live HUD Lock (ported from PushFPS, GPL-3.0-or-later): per-pixel HUD mask and compose.
veyra_add_compute_shader(veyra_shader_hud_lock_update HudLockUpdate)
veyra_add_compute_shader(veyra_shader_hud_lock_dynamic HudLockDynamic)
veyra_add_compute_shader(veyra_shader_hud_lock_fill HudLockFill)
veyra_add_compute_shader(veyra_shader_hud_lock_compose HudLockCompose)
veyra_add_compute_shader(veyra_shader_hud_protect_motion HudProtectMotion)
veyra_add_compute_shader(veyra_shader_hud_protect_detect HudProtectDetect)
veyra_add_compute_shader(veyra_shader_hud_protect_repair HudProtectRepair)
veyra_add_compute_shader(veyra_shader_hud_protect_flow HudProtectFlow)
veyra_add_compute_shader(veyra_shader_hud_protect_compose HudProtectCompose)
# Nv12Upload: byte buffer -> luma/chroma planes (copy-free upload path).
veyra_add_compute_shader(veyra_shader_nv12_upload Nv12Upload)
# PresentBlit: fullscreen-triangle pixel blit onto flip-model back buffers.
veyra_add_graphics_shader_pair(veyra_shader_present_blit PresentBlit)
veyra_add_graphics_shader_pair(veyra_shader_fullscreen_frame_stats FullscreenFrameStats)
veyra_add_compute_shader(veyra_shader_present_motion PresentMotion)
veyra_add_compute_shader(veyra_shader_hdr_coverage HdrCurveCoverage)
# NvofDensify: SHORT2 S10.5 raw flow -> workingExtent float2 + confidence.
veyra_add_compute_shader(veyra_shader_nvof_densify NvofDensify)
veyra_add_compute_shader(veyra_shader_nr_downsample NrDownsample)
veyra_add_compute_shader(veyra_shader_nr_residual NrResidualComposite)
veyra_add_compute_shader(veyra_shader_nr_temporal NrTemporal)
# Stage-5 output stabiliser (anti-flicker, default off).
veyra_add_compute_shader(veyra_shader_nr_hold NrHold)
# NR inference reuse (realtime preview only, default off).
veyra_add_compute_shader(veyra_shader_nr_reuse_compose NrReuseCompose)
veyra_add_compute_shader(veyra_shader_nr_reuse_warp NrReuseWarp)
veyra_add_compute_shader(veyra_shader_flow_adapt FlowAdapt)
veyra_add_compute_shader(veyra_shader_flow_refine FlowRefine)
veyra_add_compute_shader(veyra_shader_flow_fill FlowFill)
veyra_add_compute_shader(veyra_shader_flow_claim FlowClaim)
# VfgShotChange: per-pair shot-change test for VFG (replaces the SDK's automatic one).
veyra_add_compute_shader(veyra_shader_vfg_shot_change VfgShotChange)
# RIFE (RifeDmlBackend): colour <-> planar model tensors.
veyra_add_compute_shader(veyra_shader_rife_pack RifePack)
veyra_add_compute_shader(veyra_shader_rife_unpack RifeUnpack)
veyra_add_compute_shader(veyra_shader_rife_shot_change RifeShotChange)
veyra_add_compute_shader(veyra_shader_rgb_nv12 RgbToNv12)
veyra_add_compute_shader(veyra_shader_virtual_camera_nv12 VirtualCameraNv12)

# ---------------------------------------------------------------------------
# veyra_parity: RenoDX-equivalent codec reference (CPU golden + shaders later).
# The CPU reference has no D3D12 dependency, so it builds unconditionally.
# ---------------------------------------------------------------------------
add_library(veyra_parity STATIC
  src/parity/RenoDxParityCodec.cpp
)
veyra_apply_warnings(veyra_parity)
target_compile_features(veyra_parity PUBLIC cxx_std_20)
target_link_libraries(veyra_parity PUBLIC veyra_base)

# Guidance product library (Playbook R3/R4): providers produce the unified
# GuidanceFrame. First real member: ZeroGuidanceProvider (honest fallback).
# NvofGuidanceProvider moves in from player_probe during R3.2.
add_library(veyra_guidance STATIC
  src/guidance/ZeroGuidanceProvider.cpp
)
veyra_apply_warnings(veyra_guidance)
target_compile_options(veyra_guidance PRIVATE /WX-)
target_compile_features(veyra_guidance PRIVATE cxx_std_20)
target_compile_definitions(veyra_guidance PRIVATE
  UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
target_include_directories(veyra_guidance PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_link_libraries(veyra_guidance PUBLIC veyra_pipeline veyra_gfx veyra_base d3d12 dxgi dxguid)

# Pipeline product library (Playbook R2/R3): data contracts + reset coordinator.
# Grows in R3 as the real GPU graph migrates out of the probes.
add_library(veyra_pipeline STATIC
  src/pipeline/ResetCoordinator.cpp
  src/pipeline/ColorGradeTables.cpp
  src/pipeline/ColorGradeInstance.cpp
  src/pipeline/ColorDetailPass.cpp
  src/pipeline/AntiAliasPass.cpp
  src/pipeline/SmaaLookupTables.cpp
  src/pipeline/NrInstance.cpp
  src/pipeline/AmdHipPreflight.cpp
  src/pipeline/LmxxfNrBackend.cpp
  src/pipeline/Rdna3NrBackend.cpp
  src/pipeline/VfgBackend.cpp
  src/pipeline/VfgAmpereCompat.cpp
  src/pipeline/VfxSrBackend.cpp
)
veyra_apply_warnings(veyra_pipeline)
# FFmpeg/NVOF headers are third-party: /WX stays off for this target.
target_compile_options(veyra_pipeline PRIVATE /WX-)
target_compile_features(veyra_pipeline PRIVATE cxx_std_20)
target_compile_definitions(veyra_pipeline PUBLIC
  UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX
  VEYRA_SHADER_DIR="${CMAKE_BINARY_DIR}/shaders")
target_include_directories(veyra_pipeline PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
set(VEYRA_CUDA_DRIVER_INCLUDE_DIR "" CACHE PATH "External CUDA driver headers for native VFG (never vendored)")
if(EXISTS "${VEYRA_CUDA_DRIVER_INCLUDE_DIR}/cuda.h")
  target_include_directories(veyra_pipeline PRIVATE "${VEYRA_CUDA_DRIVER_INCLUDE_DIR}")
  target_compile_definitions(veyra_pipeline PRIVATE VEYRA_HAVE_CUDA_DRIVER_HEADERS=1)
endif()
target_link_libraries(veyra_pipeline PUBLIC veyra_base veyra_gfx d3d12 dxgi dxguid d3dcompiler)
add_dependencies(veyra_pipeline veyra_shader_rdna3_nr_decode)

# Optional independent RX7000 network worker. All third-party source and runtime
# assets remain external; only our host and reproducible preparation script live here.
set(VEYRA_RDNA3_NETWORK_SOURCE_DIR "" CACHE PATH "Prepared external RedDuke network source (MIT)")
if(EXISTS "${VEYRA_RDNA3_NETWORK_SOURCE_DIR}/runtime/core/network.cpp")
  add_executable(veyra_amd_nr_worker src/pipeline/Rdna3NrWorker.cpp "${VEYRA_RDNA3_NETWORK_SOURCE_DIR}/runtime/core/network.cpp")
  target_include_directories(veyra_amd_nr_worker PRIVATE include "${VEYRA_RDNA3_NETWORK_SOURCE_DIR}")
  target_compile_features(veyra_amd_nr_worker PRIVATE cxx_std_20)
  target_compile_definitions(veyra_amd_nr_worker PRIVATE NOMINMAX UNICODE _UNICODE WIN32_LEAN_AND_MEAN)
  target_compile_options(veyra_amd_nr_worker PRIVATE /utf-8 /WX-)
  target_link_libraries(veyra_amd_nr_worker PRIVATE d3d12 dxgi dxguid version)
endif()
# Issue 88: the AMD HIP self-test child, its class ladder and its result lines.
add_dependencies(veyra_pipeline veyra_shader_color_grade veyra_shader_color_detail_reduce veyra_shader_color_detail_blur veyra_shader_color_detail_apply)
# Spatial anti-aliasing (#53): FXAA / SMAA / MLAA ported from SAOG0721/Magpie
# d687997 (sources and notices: THIRD_PARTY_NOTICES.md). Quality tiers of one
# source are separate .dxil variants.
veyra_add_compute_shader(veyra_shader_video_denoise VideoDenoise)
add_dependencies(veyra_pipeline veyra_shader_video_denoise)
veyra_add_compute_shader(veyra_shader_aa_luma AaLuma)
veyra_add_compute_shader_variant(veyra_shader_aa_fxaa3 AaFxaa AaFxaa3 FXAA_PRESET=3)
veyra_add_compute_shader_variant(veyra_shader_aa_fxaa4 AaFxaa AaFxaa4 FXAA_PRESET=4)
veyra_add_compute_shader_variant(veyra_shader_aa_fxaa5 AaFxaa AaFxaa5 FXAA_PRESET=5)
veyra_add_compute_shader(veyra_shader_aa_smaa_edges AaSmaaEdges)
veyra_add_compute_shader_variant(veyra_shader_aa_smaa_weights_low AaSmaaWeights AaSmaaWeightsLow SMAA_PRESET_LOW)
veyra_add_compute_shader_variant(veyra_shader_aa_smaa_weights_medium AaSmaaWeights AaSmaaWeightsMedium SMAA_PRESET_MEDIUM)
veyra_add_compute_shader_variant(veyra_shader_aa_smaa_weights_high AaSmaaWeights AaSmaaWeightsHigh SMAA_PRESET_HIGH)
veyra_add_compute_shader_variant(veyra_shader_aa_smaa_weights_ultra AaSmaaWeights AaSmaaWeightsUltra SMAA_PRESET_ULTRA)
veyra_add_compute_shader(veyra_shader_aa_smaa_blend AaSmaaBlend)
veyra_add_compute_shader(veyra_shader_aa_temporal AaTemporalResolve)
veyra_add_compute_shader(veyra_shader_aa_mlaa_edges AaMlaaEdges)
veyra_add_compute_shader(veyra_shader_aa_mlaa_counts AaMlaaCounts)
veyra_add_compute_shader(veyra_shader_aa_mlaa_blend AaMlaaBlend)
# DLAA in HDR: adds the input's out-of-BT.709 part back to the DLSS result.
veyra_add_compute_shader(veyra_shader_dlaa_hdr_restore DlaaHdrRestore)
add_dependencies(veyra_pipeline veyra_shader_aa_luma veyra_shader_aa_fxaa3 veyra_shader_aa_fxaa4 veyra_shader_aa_fxaa5
  veyra_shader_aa_smaa_edges veyra_shader_aa_smaa_weights_low veyra_shader_aa_smaa_weights_medium
  veyra_shader_aa_smaa_weights_high veyra_shader_aa_smaa_weights_ultra veyra_shader_aa_smaa_blend veyra_shader_aa_temporal
  veyra_shader_aa_mlaa_edges veyra_shader_aa_mlaa_counts veyra_shader_aa_mlaa_blend veyra_shader_dlaa_hdr_restore)

# Header-only PCM gain checks do not need audio hardware, Qt or GPU runtimes.

# Standalone scene analyzer tool (phase5 gate expects veyra_scene_analyzer.exe).

# NVOF probe tool (phase5 gate expects veyra_nvof_probe.exe).
set(VEYRA_NVOF_SDK_ROOT "" CACHE PATH "NVIDIA Optical Flow SDK root")
if(VEYRA_NVOF_SDK_ROOT AND EXISTS "${VEYRA_NVOF_SDK_ROOT}/NvOFInterface/nvOpticalFlowCommon.h")
  # Reusable NVOF D3D12 session (Phase 6 motion guidance for DLSSG).
  add_library(veyra_nvof STATIC src/ngx/NvOfSession.cpp)
  veyra_apply_warnings(veyra_nvof)
  target_compile_features(veyra_nvof PUBLIC cxx_std_20)
  target_include_directories(veyra_nvof PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    "${VEYRA_NVOF_SDK_ROOT}/NvOFInterface"
    "${VEYRA_NVOF_SDK_ROOT}/Common/NvOFBase")
  target_link_libraries(veyra_nvof PUBLIC veyra_base veyra_gfx)

  # s9-A3: table-driven null-argument fault injection for NvOfSession.
endif()

# Resolve FFmpeg before any consumer, including the shared enhancement graph.
if(VEYRA_FFMPEG_ROOT AND EXISTS "${VEYRA_FFMPEG_ROOT}/include/libavformat/avformat.h")
  list(APPEND CMAKE_MODULE_PATH "${VEYRA_FFMPEG_ROOT}/share/ffmpeg")
  find_package(FFMPEG REQUIRED)
endif()

# EnhanceGraph (the real GPU chain) needs the NGX + NVOF backends; wire it
# into veyra_pipeline only when both exist so bare contract builds still work.
if(TARGET veyra_ngx AND TARGET veyra_nvof AND VEYRA_FFMPEG_ROOT)
  target_sources(veyra_pipeline PRIVATE src/pipeline/EnhanceGraph.cpp src/pipeline/NisScaler.cpp src/pipeline/HudLock.cpp src/pipeline/HudProtect.cpp src/pipeline/NrTemporalPass.cpp src/pipeline/NrHoldPass.cpp src/pipeline/NrReusePass.cpp src/core/SceneCadenceAnalyzer.cpp)
  target_include_directories(veyra_pipeline PRIVATE ${FFMPEG_INCLUDE_DIRS})
  target_link_libraries(veyra_pipeline PRIVATE veyra_ngx veyra_nvof ${FFMPEG_LIBRARIES})
  add_dependencies(veyra_pipeline
    veyra_shader_yuv_to_rgb veyra_shader_rgb_to_linear veyra_shader_parity_encode
    veyra_shader_parity_decode veyra_shader_scale_blit veyra_shader_nis
    veyra_shader_hdr_amd_nr_encode veyra_shader_hdr_amd_nr_restore
    veyra_shader_nv12_upload veyra_shader_nvof_densify veyra_shader_packed_capture)
endif()

# ---------------------------------------------------------------------------
# veyra_media: FFmpeg demux/decode (Phase 3). Links only the Playbook 3.4
# dependency set from the pinned vcpkg install.
# ---------------------------------------------------------------------------
if(VEYRA_FFMPEG_ROOT AND EXISTS "${VEYRA_FFMPEG_ROOT}/include/libavformat/avformat.h")
  add_library(veyra_media STATIC
    src/media/FFmpegDemuxer.cpp
    src/media/DemuxSession.cpp
    src/media/FFmpegVideoDecoder.cpp
    src/media/FFmpegDeinterlacer.cpp
    src/media/FfmpegLog.cpp
  )
  veyra_apply_warnings(veyra_media)
  # FFmpeg headers are third-party; /WX stays off for this target
  # (Playbook 5.3: never let third-party headers block the build).
  target_compile_options(veyra_media PRIVATE /WX-)
  target_compile_features(veyra_media PUBLIC cxx_std_20)
  # d3d11: the HEVC hardware path decodes on a private D3D11VA device and shares
  # the surfaces with the D3D12 graph as NT handles.
  target_link_libraries(veyra_media PUBLIC veyra_base veyra_gfx d3d11 bcrypt winhttp)
  if(VEYRA_ENABLE_DEINTERLACE)
    if(NOT EXISTS "${VEYRA_FFMPEG_ROOT}/include/libavfilter/avfilter.h")
      message(FATAL_ERROR "Deinterlacing requires the filter prefix; run scripts/ffmpeg/build-deinterlace-module.py and set VEYRA_FFMPEG_ROOT to its prefix (or explicitly disable VEYRA_ENABLE_DEINTERLACE).")
    endif()
    target_compile_definitions(veyra_media PRIVATE VEYRA_ENABLE_DEINTERLACE=1)
    # A reused build tree may retain FFMPEG_INCLUDE_DIRS from the pre-filter
    # prefix. Compile against the prefix whose filter headers we just checked.
    target_include_directories(veyra_media BEFORE PRIVATE "${VEYRA_FFMPEG_ROOT}/include")
  endif()
  target_include_directories(veyra_media PUBLIC ${FFMPEG_INCLUDE_DIRS})
  target_link_directories(veyra_media PUBLIC ${FFMPEG_LIBRARY_DIRS})
  target_link_libraries(veyra_media PUBLIC ${FFMPEG_LIBRARIES})
  # libdovi (MIT): parses the RPU payload itself, including streams whose RPU sits
  # in the enhancement layer with no dovi_config record for FFmpeg to follow.
  option(VEYRA_ENABLE_LIBDOVI "Parse Dolby Vision RPU carried in enhancement-layer streams" ON)
  set(VEYRA_LIBDOVI_ROOT "" CACHE PATH "External libdovi prefix; binaries/SDK stay outside source Git")
  if(VEYRA_ENABLE_LIBDOVI)
    find_path(VEYRA_LIBDOVI_INCLUDE libdovi/rpu_parser.h HINTS "${VEYRA_LIBDOVI_ROOT}/include")
    find_library(VEYRA_LIBDOVI_LIBRARY NAMES dolby_vision.dll dovi libdovi HINTS "${VEYRA_LIBDOVI_ROOT}/lib")
    find_file(VEYRA_LIBDOVI_RUNTIME NAMES dolby_vision.dll dovi.dll libdovi.dll HINTS "${VEYRA_LIBDOVI_ROOT}/bin")
    if(NOT VEYRA_LIBDOVI_INCLUDE OR NOT VEYRA_LIBDOVI_LIBRARY OR NOT VEYRA_LIBDOVI_RUNTIME)
      message(FATAL_ERROR "libdovi enabled: provide VEYRA_LIBDOVI_ROOT with matching include/lib/bin; see docs/PR_INTEGRATION_PLAN_2026-11-18.md. Explicitly disable VEYRA_ENABLE_LIBDOVI only for a reduced developer build.")
    endif()
    add_library(veyra_libdovi INTERFACE)
    target_include_directories(veyra_libdovi INTERFACE "${VEYRA_LIBDOVI_INCLUDE}")
    # Keep link.exe response files free of non-ANSI dependency paths.
    configure_file("${VEYRA_LIBDOVI_LIBRARY}" "${CMAKE_CURRENT_BINARY_DIR}/veyra-libdovi.lib" COPYONLY)
    target_link_libraries(veyra_libdovi INTERFACE "${CMAKE_CURRENT_BINARY_DIR}/veyra-libdovi.lib")
    target_compile_definitions(veyra_libdovi INTERFACE VEYRA_HAVE_LIBDOVI=1)
    target_link_libraries(veyra_media PUBLIC veyra_libdovi)
    message(STATUS "libdovi external runtime: ${VEYRA_LIBDOVI_RUNTIME}")
  endif()

  # veyra_sinks: product output sinks (Playbook R3). First member is the
  # WASAPI audio sink extracted verbatim from player_probe; D3D12PresentSink
  # currently lives in veyra_gfx and moves here when the migration completes.
  add_library(veyra_sinks STATIC
    src/sink/WasapiAudioSink.cpp
    src/sink/CaptureAudioSession.cpp
    src/sink/CaptureAudioDsp.cpp
    src/sink/BitstreamAudio.cpp
    src/sink/BitstreamAudioSink.cpp
    src/sink/HdmiBitstreamOutput.cpp
    src/sink/Iec61937Burst.cpp
    src/sink/ImageExportSink.cpp
    src/sink/NvencD3D12Encoder.cpp
    src/sink/NvencLiveEncoder.cpp
    src/sink/MfVideoEncoder.cpp
    src/sink/RecordingAudioTap.cpp
    src/sink/SystemAudioLoopback.cpp
    src/sink/VideoEncoderFactory.cpp
  )
  veyra_apply_warnings(veyra_sinks)
  target_compile_options(veyra_sinks PRIVATE /WX-)
  target_compile_features(veyra_sinks PRIVATE cxx_std_20)
  target_compile_definitions(veyra_sinks PRIVATE
    UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
  set_source_files_properties(src/sink/HdmiBitstreamOutput.cpp PROPERTIES COMPILE_DEFINITIONS VEYRA_HDMI_BITSTREAM_DIAGNOSTICS)
  target_include_directories(veyra_sinks PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
  target_include_directories(veyra_sinks PRIVATE ${FFMPEG_INCLUDE_DIRS})
  set(VEYRA_NVENC_HEADERS_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/third_party_local/nvidia/nv-codec-headers-13.0" CACHE PATH "NVENC 13.0 ABI headers (nv-codec-headers n13.0.19.0)")
  if(NOT EXISTS "${VEYRA_NVENC_HEADERS_ROOT}/include/ffnvcodec/nvEncodeAPI.h")
    message(FATAL_ERROR "Stage nv-codec-headers n13.0.19.0 at VEYRA_NVENC_HEADERS_ROOT; see THIRD_PARTY_NOTICES.md")
  endif()
  target_include_directories(veyra_sinks PRIVATE "${VEYRA_NVENC_HEADERS_ROOT}/include")
  target_compile_definitions(veyra_sinks PRIVATE VEYRA_SHADER_DIR="${CMAKE_BINARY_DIR}/shaders")
  add_dependencies(veyra_sinks veyra_shader_rgb_nv12)
  # veyra_media: AudioPipeline reads packets from the shared network demux session (#48).
  target_link_libraries(veyra_sinks PUBLIC veyra_base veyra_gfx veyra_media ole32 windowscodecs mmdevapi avrt mfplat mfuuid mf)
  add_subdirectory(third_party/soundtouch EXCLUDE_FROM_ALL)
  target_link_libraries(veyra_sinks PRIVATE ${FFMPEG_LIBRARIES} veyra_soundtouch)
  if(FFMPEG_INCLUDE_DIRS)
    target_include_directories(veyra_sinks PRIVATE ${FFMPEG_INCLUDE_DIRS})
  endif()

  # veyra_sources: product input sources (Playbook R3/R7). MediaFileSource
  # composes veyra_media; no second decode implementation exists.
  add_dependencies(veyra_pipeline veyra_shader_effect_exclusion veyra_shader_hud_lock_update veyra_shader_hud_lock_dynamic veyra_shader_hud_lock_fill veyra_shader_hud_lock_compose veyra_shader_hud_protect_motion veyra_shader_hud_protect_detect veyra_shader_hud_protect_repair veyra_shader_hud_protect_flow veyra_shader_hud_protect_compose veyra_shader_sr_resolve veyra_shader_nr_downsample veyra_shader_nr_residual veyra_shader_nr_temporal veyra_shader_nr_hold veyra_shader_nr_reuse_compose veyra_shader_nr_reuse_warp veyra_shader_flow_adapt veyra_shader_flow_refine veyra_shader_flow_fill veyra_shader_flow_claim veyra_shader_vfg_shot_change veyra_shader_rife_pack veyra_shader_rife_unpack veyra_shader_rife_shot_change)
  add_library(veyra_sources STATIC
    src/source/ScreenCaptureSource.cpp
    src/source/VirtualDesktop.cpp
  )
  veyra_apply_warnings(veyra_sources)
  target_compile_options(veyra_sources PRIVATE /WX-)
  target_compile_features(veyra_sources PRIVATE cxx_std_20)
  target_link_libraries(veyra_sources PUBLIC veyra_sinks)
  target_compile_definitions(veyra_sources PRIVATE
    UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_include_directories(veyra_sources PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
  target_link_libraries(veyra_sources PUBLIC veyra_pipeline veyra_media veyra_base)
  target_link_libraries(veyra_sources PRIVATE ${FFMPEG_LIBRARIES} strmiids ole32 oleaut32 d3d12 dxgi cfgmgr32)
  # Matching FFmpeg imports and external libdovi propagate through veyra_media.
  target_link_libraries(veyra_sources PRIVATE d3d11 windowsapp dwmapi)




  # #48: shared demux session, reconnect, buffering, damaged-data tolerance (tests/network).

  # Frame pacing repair and the adaptive multiplier (ported from PushFPS): header-only logic.
  # Live HUD Lock on a real D3D12 device (ported from PushFPS).
  # NVENC recording tuning (two-pass, psycho-visual AQ; options from PushFPS).
  # veyra_engine is linked for the subtitle engine (SRT/ASS/VTT parsing +
  # indexed cue lookup); FFmpeg import libraries come from its public surface.
  # This suite keeps many EnhancementSettings copies and P5 RPU blobs alive at once;
  # the default 1 MiB stack overflowed after the 2.0.7 test/struct growth (verified: it
  # completes with a larger stack). Same remedy the other suites already use.

  # main() holds hundreds of 8 KB EnhancementSettings copies; the 1 MB default stack overflowed partway (2.1.0).

  # Custom (Dolby Vision profile 5): runs the shipped YuvToLinearRgb.dxil over a
  # decoded frame with the player's own root constants and dumps the working
  # signal, so the profile-5 colour conversion can be diffed against an
  # independent reference decode instead of being taken on trust.
# Everything that touches media headers (NetworkInput, Dovi, the audio tests) needs these.
# Upstream relies on its own build environment exporting them; we add them globally.
include_directories(${FFMPEG_INCLUDE_DIRS})

  # The FSR probes include the FidelityFX SDK headers directly, so they cannot be built
  # without the local SDK tree (same guard as the FSR backend above). They are diagnostic
  # tools only; the player and the tests do not need them.
  # Its headers carry UTF-8 Chinese literals (CaptureBuffer.h, EnhancementSettings.h).
  # wmain holds many PlayerSnapshot locals; the default 1 MiB stack overflowed at entry.

  # Qt 6.8.3 is staged under deps/ (the user allowed the latest Qt). The probe is
# opt-in so a normal product build never depends on Qt being present.
option(VEYRA_BUILD_QT_PROBE "Build the Qt + D3D12 host probe" OFF)
option(VEYRA_BUILD_QML_UI "Build the QML front end" OFF)
if(VEYRA_BUILD_QT_PROBE OR VEYRA_BUILD_QML_UI)
  find_package(Qt6 6.8 QUIET COMPONENTS Core Gui Qml Quick QuickControls2 Widgets Network)
endif()

# The QML bridge. It is engine code (no QML files), so it compiles into a
# separate small library rather than into veyra_engine: the product build must
# never depend on Qt being installed.
if(VEYRA_BUILD_QML_UI AND Qt6_FOUND)
  # The 日落 palette's startup music (StartupMusic.h): Media Foundation's media engine.
  add_library(veyra_startup_music STATIC src/ui/StartupMusic.cpp include/veyra/ui/StartupMusic.h)
  set_target_properties(veyra_startup_music PROPERTIES AUTOMOC ON)
  target_compile_features(veyra_startup_music PUBLIC cxx_std_20)
  target_compile_options(veyra_startup_music PRIVATE /utf-8)
  target_include_directories(veyra_startup_music PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
  target_link_libraries(veyra_startup_music PUBLIC veyra_base Qt6::Core PRIVATE ole32 oleaut32 mfplat mfuuid)
  set(VEYRA_UPDATE_PUBLIC_KEY "" CACHE STRING "Ed25519 release verification key as 64 lowercase hex digits")
  set(VEYRA_UPDATE_TEST_PORT "" CACHE STRING "Local HTTP update fixture port (test builds only)")
  string(LENGTH "${VEYRA_UPDATE_PUBLIC_KEY}" veyra_update_key_length)
  if(VEYRA_UPDATE_PUBLIC_KEY AND
     (NOT veyra_update_key_length EQUAL 64 OR NOT VEYRA_UPDATE_PUBLIC_KEY MATCHES "^[0-9a-f]+$"))
    message(FATAL_ERROR "VEYRA_UPDATE_PUBLIC_KEY must be a 32-byte Ed25519 public key in lowercase hex")
  endif()
  find_package(OpenSSL 1.1.1 REQUIRED COMPONENTS Crypto)
  add_library(veyra_portable_manifest STATIC src/base/PortableUpdateManifest.cpp)
  target_compile_features(veyra_portable_manifest PUBLIC cxx_std_20)
  target_compile_definitions(veyra_portable_manifest PRIVATE VEYRA_UPDATE_PUBLIC_KEY="${VEYRA_UPDATE_PUBLIC_KEY}")
  if(VEYRA_UPDATE_TEST_PORT)
    if(NOT VEYRA_UPDATE_TEST_PORT MATCHES "^[1-9][0-9]*$" OR VEYRA_UPDATE_TEST_PORT GREATER 65535
       OR NOT VEYRA_DISPLAY_VERSION MATCHES "-.*test")
      message(FATAL_ERROR "The loopback update server requires a valid port and a test display version")
    endif()
    target_compile_definitions(veyra_portable_manifest PRIVATE VEYRA_UPDATE_TEST_PORT=${VEYRA_UPDATE_TEST_PORT})
  endif()
  if(VEYRA_UPDATE_TEST_PORT)
    set(veyra_update_test_build true)
  else()
    set(veyra_update_test_build false)
  endif()
  file(GENERATE OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/portable-update-trust.json"
    CONTENT "{\"publicKey\":\"${VEYRA_UPDATE_PUBLIC_KEY}\",\"testBuild\":${veyra_update_test_build}}\n")
  target_include_directories(veyra_portable_manifest PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/include")
  target_link_libraries(veyra_portable_manifest PUBLIC Qt6::Core PRIVATE OpenSSL::Crypto ws2_32 crypt32)

  add_executable(veyra_portable_launcher WIN32 apps/veyra-portable/Launcher.cpp)
  target_compile_features(veyra_portable_launcher PRIVATE cxx_std_20)
  target_compile_options(veyra_portable_launcher PRIVATE /utf-8)
  target_compile_definitions(veyra_portable_launcher PRIVATE UNICODE _UNICODE NOMINMAX WIN32_LEAN_AND_MEAN)
  target_include_directories(veyra_portable_launcher PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/include")
  target_link_libraries(veyra_portable_launcher PRIVATE veyra_base shell32 user32)
  add_executable(veyra_update_worker apps/veyra-portable/UpdateWorker.cpp)
  set_target_properties(veyra_portable_launcher PROPERTIES OUTPUT_NAME OverRez)
  set_target_properties(veyra_update_worker PROPERTIES OUTPUT_NAME OverRezUpdate)
  target_compile_definitions(veyra_update_worker PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN)
  target_link_libraries(veyra_update_worker PRIVATE veyra_portable_manifest ole32 uuid)
  add_library(veyra_update_checker STATIC src/ui/UpdateChecker.cpp include/veyra/ui/UpdateChecker.h
    src/ui/PortableUpdate.cpp include/veyra/ui/PortableUpdate.h)
  set_target_properties(veyra_update_checker PROPERTIES AUTOMOC ON)
  target_compile_features(veyra_update_checker PUBLIC cxx_std_20)
  target_compile_options(veyra_update_checker PRIVATE /utf-8)
  target_include_directories(veyra_update_checker PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
  target_link_libraries(veyra_update_checker PUBLIC Qt6::Core Qt6::Gui Qt6::Network veyra_portable_manifest)
  add_library(veyra_qml_bridge STATIC src/ui/QmlPlayerBridge.cpp
    src/ui/LiveTranslation.cpp src/ui/LiveTranslation.h
    src/ui/LiveSentences.cpp src/ui/LiveSentences.h
    src/ui/LiveAsr.cpp src/ui/LiveAsr.h
    src/ui/AsrAudioTap.cpp src/ui/AsrAudioTap.h
    src/ui/AsrModels.cpp src/ui/AsrModels.h
    src/ui/AsrWorker.cpp src/ui/AsrWorker.h
    src/ui/TranslationAssets.cpp src/ui/TranslationAssets.h
    src/ui/WinCaptionReader.cpp src/ui/WinCaptionReader.h
    include/veyra/ui/QmlPlayerBridge.h
    # Custom: the start-up format badge, same layered-window construction.
    src/media/FormatBadgeWindow.cpp
    # P4-c: the existing subtitle renderer, reused as-is (no second renderer).
    apps/veyra/ui/SubtitleOverlay.cpp)
  set_source_files_properties(apps/veyra/ui/SubtitleOverlay.cpp PROPERTIES COMPILE_OPTIONS /utf-8)
  # AUTOMOC: QmlPlayerBridge declares Q_OBJECT, so its meta-object has to be
  # generated. Without this the library links but every signal is unresolved.
  # Keep bridge domains explicit: no source glob or duplicate runtime state.
  target_sources(veyra_qml_bridge PRIVATE
    src/ui/NvidiaVrrProfileController.cpp
    include/veyra/ui/NvidiaVrrProfileController.h
    src/ui/bridge/Hardware.cpp
    src/ui/bridge/Status.cpp
    src/ui/bridge/FrameGeneration.cpp
    src/ui/bridge/Colour.cpp
    src/ui/bridge/Preferences.cpp
    src/ui/bridge/AnrDownload.cpp
    src/ui/bridge/Capture.cpp
    src/ui/bridge/Export.cpp
    src/ui/bridge/Subtitles.cpp
    src/ui/bridge/Playback.cpp
    src/ui/bridge/Enhancement.cpp
    src/ui/bridge/Chain.cpp
    src/ui/bridge/Recording.cpp
    src/ui/bridge/VirtualCamera.cpp
    src/ui/bridge/View.cpp
    # Custom (Chrome bridge): local HTTP endpoint the browser extension posts to.
    src/ui/QmlPlayerBridge_p.h)
  set_target_properties(veyra_qml_bridge PROPERTIES AUTOMOC ON)
  # Interface language (UiLanguage.h): its own small library so the streaming models,
  # which are tested without the player, translate their messages too.
  add_library(veyra_ui_i18n STATIC src/ui/UiLanguage.cpp include/veyra/ui/UiLanguage.h)
  target_compile_features(veyra_ui_i18n PUBLIC cxx_std_20)
  target_compile_options(veyra_ui_i18n PRIVATE /utf-8)
  target_include_directories(veyra_ui_i18n PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
  target_link_libraries(veyra_ui_i18n PUBLIC veyra_base Qt6::Core)
  target_link_libraries(veyra_qml_bridge PUBLIC veyra_ui_i18n veyra_update_checker)
  target_compile_features(veyra_qml_bridge PRIVATE cxx_std_20)
  target_include_directories(veyra_qml_bridge PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include ${CMAKE_CURRENT_SOURCE_DIR}/src ${FFMPEG_INCLUDE_DIRS}
    ${CMAKE_CURRENT_SOURCE_DIR}/apps/veyra/ui)
  # Widgets is needed only for QFileDialog: the native file picker is the one
  # piece of the old shell worth keeping, and its own dialog is what users
  # expect from a desktop app. No QWidget UI is created.
  target_link_libraries(veyra_qml_bridge PUBLIC veyra_engine Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::QuickControls2 Qt6::Widgets Qt6::Network PRIVATE shell32 ole32 oleaut32 uiautomationcore iphlpapi ws2_32 ${FFMPEG_LIBRARIES})
  find_package(Qt6 COMPONENTS Test)
  # VEYRA_DISPLAY_VERSION is the human-readable version the app reports; it is
  # the same value the resource file uses, so the UI cannot drift from it.
  target_compile_definitions(veyra_qml_bridge PRIVATE VEYRA_DISPLAY_VERSION="${VEYRA_DISPLAY_VERSION}")
  # OverRez has its own version line (OVERREZ_VERSION); the project version stays the
  # upstream Veyra release it is based on, which the release workflow repacks.
  file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/OVERREZ_VERSION" OVERREZ_VERSION LIMIT_COUNT 1)
  target_compile_definitions(veyra_qml_bridge PRIVATE OVERREZ_VERSION="${OVERREZ_VERSION}")
  # libass (ISC) + FreeType/FriBidi/HarfBuzz, static, for full ASS/SSA effect
  # subtitles. Local prebuilt tree only (vcpkg x64-windows-static-md); never in
  # source Git. Without it ASS tracks fall back to the built-in styled renderer.
  set(VEYRA_LIBASS_ROOT "" CACHE PATH "libass static install prefix (include/ass/ass.h, lib/ass.lib)")
  if(VEYRA_LIBASS_ROOT AND EXISTS "${VEYRA_LIBASS_ROOT}/include/ass/ass.h")
    target_sources(veyra_qml_bridge PRIVATE apps/veyra/ui/AssSubtitleRenderer.cpp apps/veyra/ui/AssSubtitleRenderer.h)
    set_source_files_properties(apps/veyra/ui/AssSubtitleRenderer.cpp PROPERTIES COMPILE_OPTIONS /utf-8)
    target_include_directories(veyra_qml_bridge PRIVATE "${VEYRA_LIBASS_ROOT}/include")
    target_compile_definitions(veyra_qml_bridge PRIVATE VEYRA_HAS_LIBASS=1)
    foreach(lib ass harfbuzz fribidi freetype libpng16 zs bz2 brotlidec brotlicommon)
      target_link_libraries(veyra_qml_bridge PRIVATE "${VEYRA_LIBASS_ROOT}/lib/${lib}.lib")
    endforeach()
    target_link_libraries(veyra_qml_bridge PRIVATE gdi32 dwrite)
    message(STATUS "libass: ${VEYRA_LIBASS_ROOT}")
  else()
    message(STATUS "libass: not configured; ASS effects use the built-in styled renderer")
  endif()

  # The QML module is deployed as plain files next to the executable rather
  # than compiled into a resource: the qmldir-based module keeps the .qml
  # editable in a build tree, which matters while the interface is still being
  # worked on. A packaged release can switch to compiling them in.
  # WIN32: a GUI subsystem binary. Without it a console window follows the app
  # around, which is not what a player should look like. Diagnostics still reach
  # the log file through the logger.
  add_executable(veyra_qml_ui WIN32 apps/veyra-qml/main.cpp apps/veyra-qml/ProfileInstance.cpp
    src/ui/QmlDataDirectory.cpp src/ui/QmlDiskCache.cpp)
  set_target_properties(veyra_qml_ui PROPERTIES OUTPUT_NAME OverRezApp)
  add_dependencies(veyra_qml_ui veyra_virtualcam_components)
  if(VEYRA_UPDATE_PUBLIC_KEY)
    add_dependencies(veyra_qml_ui veyra_portable_launcher veyra_update_worker)
  endif()
  if(VEYRA_UPDATE_TEST_PORT)
    target_compile_definitions(veyra_qml_ui PRIVATE VEYRA_PORTABLE_UPDATE_TEST=1)
  endif()
  if(VEYRA_ENABLE_LIBDOVI)
    add_custom_target(veyra_libdovi_runtime ALL
      COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${VEYRA_LIBDOVI_RUNTIME}" "$<TARGET_FILE_DIR:veyra_qml_ui>")
    add_dependencies(veyra_qml_ui veyra_libdovi_runtime)
  endif()
  # The QML copy is its own always-run step rather than a POST_BUILD of the link:
  # its two long E:/项目 paths on the link statement pushed that command past
  # CMake's response-file threshold, and link.exe reads response files in the
  # ANSI code page (the UTF-8 Qt library paths then fail to open).
  add_custom_target(veyra_qml_files ALL
    COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_CURRENT_SOURCE_DIR}/qml ${CMAKE_CURRENT_BINARY_DIR}/qml
    COMMENT "Copying QML")
  add_dependencies(veyra_qml_ui veyra_qml_files)
  # Interface translations (设置 → 界面语言): one catalog, compiled in so a package
  # cannot ship without it. scripts/i18n/ builds it from the source strings.
  qt_add_resources(veyra_qml_ui "veyra_i18n" PREFIX "/i18n" BASE "${CMAKE_CURRENT_SOURCE_DIR}/i18n" FILES i18n/catalog.json)
  set(VEYRA_VB_CABLE_PACKAGE "" CACHE FILEPATH "Original VB-Audio Pack46 ZIP to include for optional offline installation")
  if(VEYRA_VB_CABLE_PACKAGE)
    file(SHA256 "${VEYRA_VB_CABLE_PACKAGE}" veyra_vb_cable_sha256)
    if(NOT veyra_vb_cable_sha256 STREQUAL "bc44e8974191a5a2427d6c979e2dab08dbb09925f3f435dfa2f0ba3e45b6eb90")
      message(FATAL_ERROR "VEYRA_VB_CABLE_PACKAGE must be the original VB-Audio Pack46 ZIP")
    endif()
    set_source_files_properties("${VEYRA_VB_CABLE_PACKAGE}" PROPERTIES QT_RESOURCE_ALIAS "VBCABLE_Driver_Pack46.zip")
    qt_add_resources(veyra_qml_ui "veyra_optional_vb_cable" PREFIX "/optional-drivers"
      FILES "${VEYRA_VB_CABLE_PACKAGE}" OPTIONS -no-compress)
  endif()
  target_compile_features(veyra_qml_ui PRIVATE cxx_std_20)
  # Every thread without an explicit size (UI, engine, export worker) reserves the
  # image default. The 32-node EffectChain is 45 KB and the bridge, preset and
  # engine frames hold several (2026-10-18: bridge constructor 400 KB,
  # EngineController::run 385 KB), so 1 MB no longer leaves a safe margin.
  # Reserve only: pages are committed as they are touched.
  target_link_options(veyra_qml_ui PRIVATE /STACK:8388608)
  # Qt6::CorePrivate only for QUnifiedTimer's slow mode behind --slow-animations.
  target_link_libraries(veyra_qml_ui PRIVATE veyra_qml_bridge veyra_engine veyra_startup_music Qt6::CorePrivate dbghelp ole32 rstrtmgr)

  # The per-build QML disk cache folder (QmlDiskCache.h).

  # G0.6: Theme easing curves read back through QML against the design's CSS curves.
  # Loads qml/ from the source tree; runs offscreen with the Qt bin directory on PATH.

  # G1.6: component smoke tests (Qt Quick Test), tests/qml/quick/tst_*.qml.
endif()

# Qt + D3D12 host probe (S3.0): answers whether Qt can host the native video
# swapchain window without costing present latency. Diagnostic only.

  # Stage-4 defect-audit assertions: GPU-free checks on the architecture-spoof
  # scope and the Ampere re-label policy (see docs/NR_FG_OPTIMIZATION_PLAN_2026-09-29.md).
  # Stage-6 anti-flicker tier assertions (GPU-free: enum narrowing, flat/list
  # agreement, validation, chain-node carry).
  # Stage-5 output-stabiliser acceptance (anti-flicker, default off).
  # NR inference reuse: frame selection, Auto controller and settings (GPU-free),
  # and the reuse pass on real D3D12 dispatches.
  # NR inference reuse against full inference on a real video (offline readbacks).

  # Headless quality-core runner (Playbook R3.3): the phase5 gate's quality
  add_library(veyra_engine STATIC src/engine/EngineController.cpp src/engine/EngineWatchdog.cpp src/engine/PreviewGpuSession.cpp src/engine/CaptureGraphPreparation.cpp src/engine/EffectChain.cpp src/engine/PresetLibrary.cpp src/ui/PlayerUiFacade.cpp src/engine/PresetStore.cpp src/engine/VideoPresenter.cpp src/engine/DisplayStateService.cpp src/engine/Subtitles.cpp src/engine/FgCompatibilityProbe.cpp src/engine/LiveRecorder.cpp src/engine/ReplayBuffer.cpp src/engine/MicrophoneCapture.cpp)
  target_sources(veyra_pipeline PRIVATE src/guidance/AmdOpticalFlow.cpp
    src/guidance/GpuDisOpticalFlow.cpp third_party/gpu-dis/src/gpu/native_strict_dis_provider.cpp)
  target_include_directories(veyra_pipeline PRIVATE third_party/gpu-dis/src/gpu)
  include(cmake/VeyraGpuDis.cmake)
  veyra_add_compute_shader(veyra_shader_gpu_dis_luma GpuDisLuma)
  veyra_add_compute_shader(veyra_shader_gpu_dis_validate GpuDisValidate)
  add_dependencies(veyra_pipeline veyra_shader_gpu_dis veyra_shader_gpu_dis_luma veyra_shader_gpu_dis_validate)
  if(EXISTS "${VEYRA_FIDELITYFX_ROOT}/bin/ffx_sdk/ffx_opticalflow_x64.lib")
    target_compile_definitions(veyra_pipeline PRIVATE VEYRA_HAS_AMD_OF=1)
    target_include_directories(veyra_pipeline PRIVATE "${VEYRA_FIDELITYFX_ROOT}/include")
    target_link_libraries(veyra_pipeline PRIVATE
      "${VEYRA_FIDELITYFX_ROOT}/bin/ffx_sdk/ffx_opticalflow_x64.lib"
      "${VEYRA_FIDELITYFX_ROOT}/bin/ffx_sdk/ffx_backend_dx12_x64.lib")
  endif()
  target_compile_features(veyra_engine PUBLIC cxx_std_20)
  target_sources(veyra_engine PRIVATE src/engine/VirtualCamera.cpp src/virtualcam/CameraRegistration.cpp)
  target_link_libraries(veyra_engine PUBLIC veyra_virtualcam_transport advapi32)
  # On-screen text for live translation: OCR reading logic (portable, ported from
  # VI Translator, MIT) and the Windows OCR reader of the presented picture.
  target_sources(veyra_engine PRIVATE src/engine/ScreenText.cpp src/engine/ScreenTextCapture.cpp)
  target_link_libraries(veyra_engine PRIVATE windowsapp)
  add_dependencies(veyra_engine veyra_shader_virtual_camera_nv12)
  target_compile_options(veyra_engine PRIVATE /utf-8)
  target_compile_definitions(veyra_engine PUBLIC VEYRA_PROJECT_ROOT="${CMAKE_CURRENT_SOURCE_DIR}" VEYRA_SHADER_DIR="${CMAKE_BINARY_DIR}/shaders")
  target_link_libraries(veyra_engine PUBLIC veyra_pipeline veyra_sources veyra_sinks veyra_ngx veyra_nvof)
 # Preset apply recurses over 21 KB ChainConfiguration frames; the default 1 MB stack is too close to the edge.
# veyra_base carries /utf-8 and NOMINMAX (PresetLibrary.cpp has Chinese literals and uses std::max).

  # Large independent settings/descriptor fixtures, like the preset contracts.

  # CPU bake of the colour grade: no GPU, no engine link - the tables the ingest
  # shader reads are pure maths and must be verifiable without a device.
  # GPU contract for the v4 colour chain: identity when off/neutral, exposure,
  # curve, saturation and hue, all through a real graph and its ingest pass.
  # Byte-exact regression for the effect insertion slots (colour today, more
  # effects later): one frame per configuration through the real graph, printed
  # as SHA-256 so a build from before a change can be compared with one after it.
  # GPU quality / HDR / temporal / slot / tiled / timing checks of the anti-aliasing effect (#53).
  # Beauty node: face detector, passes and their tests.
  include(cmake/VeyraBeauty.cmake)
  # Adobe .cube parsing + the runtime LUT store (CPU only).
  # Named colour looks + .vpcolor export/import (CPU only).
  add_dependencies(veyra_engine veyra_shader_hdr_video_sr veyra_shader_present_motion veyra_shader_present_blit veyra_shader_hdr_coverage veyra_shader_fullscreen_frame_stats)
  # Headless export harness: verifies the frame-timestamp policy (tail snap,
  # dropped-sample gap fill, hard refusal) without the GUI.

  # matrix executes through the shared product libraries only.

  # UI migration guard: per-frame output hashes for fixed stage configurations.

  # Headless Remote Play probe: drives the product session stack with a saved
  # profile so codec/bitrate variants can be compared without the GUI.

  # Phase 6 realtime engine probe: decode -> SR -> NR -> NVOF -> DLSSG -> present.
endif()

# Clip generator: links the openh264-enabled toolchain FFmpeg ONLY.

# Layered child subtitle windows require a modern-Windows compatibility manifest.
if(TARGET veyra_qml_ui)
  # The version resource carries the OverRez version, not the upstream engine's.
  file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/OVERREZ_VERSION" OVERREZ_RC_VERSION LIMIT_COUNT 1)
  string(REPLACE "." ";" OVERREZ_RC_PARTS "${OVERREZ_RC_VERSION}")
  list(GET OVERREZ_RC_PARTS 0 OVERREZ_VERSION_MAJOR)
  list(GET OVERREZ_RC_PARTS 1 OVERREZ_VERSION_MINOR)
  list(GET OVERREZ_RC_PARTS 2 OVERREZ_VERSION_PATCH)
  set(VEYRA_RESOURCE_FILENAME "OverRezApp.exe")
  configure_file(apps/veyra/version.rc.in ${CMAKE_CURRENT_BINARY_DIR}/veyra-qml-version.rc @ONLY)
  target_sources(veyra_qml_ui PRIVATE ${CMAKE_CURRENT_BINARY_DIR}/veyra-qml-version.rc)
  set(VEYRA_RESOURCE_FILENAME "OverRez.exe")
  configure_file(apps/veyra/version.rc.in ${CMAKE_CURRENT_BINARY_DIR}/veyra-portable-version.rc @ONLY)
  target_sources(veyra_portable_launcher PRIVATE ${CMAKE_CURRENT_BINARY_DIR}/veyra-portable-version.rc)
  set(VEYRA_RESOURCE_FILENAME "OverRezUpdate.exe")
  configure_file(apps/veyra/version.rc.in ${CMAKE_CURRENT_BINARY_DIR}/veyra-updater-version.rc @ONLY)
  target_sources(veyra_update_worker PRIVATE ${CMAKE_CURRENT_BINARY_DIR}/veyra-updater-version.rc)
endif()
configure_file(apps/veyra/resource.h ${CMAKE_CURRENT_BINARY_DIR}/veyra-resource.h COPYONLY)
configure_file(assets/overrez.ico ${CMAKE_CURRENT_BINARY_DIR}/overrez.ico COPYONLY)
if(TARGET veyra_qml_ui)
  set_source_files_properties(${CMAKE_CURRENT_BINARY_DIR}/veyra-qml-version.rc PROPERTIES
    OBJECT_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/assets/overrez.ico;${CMAKE_CURRENT_SOURCE_DIR}/apps/veyra/resource.h")
endif()
# P4-c: the QML front end hosts the same layered child subtitle window.
if(TARGET veyra_qml_ui)
  # Copied next to the link step and named relatively: a short link line keeps
  # link.exe off the (ANSI-decoded) response file.
  configure_file(apps/veyra/veyra.manifest ${CMAKE_CURRENT_BINARY_DIR}/veyra-qml.manifest COPYONLY)
  target_link_options(veyra_qml_ui PRIVATE "/MANIFESTINPUT:veyra-qml.manifest")
endif()
