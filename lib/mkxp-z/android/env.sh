set -x ARCH linux-x86_64
set -x ANDROID_HOME $HOME/Android
set -x ANDROID_NDK_HOME $ANDROID_HOME/ndk/27.3.13750724
set -x ANDROID_NDK_ROOT $ANDROID_HOME/ndk/27.3.13750724
set -x PATH $ANDROID_HOME/cmdline-tools/latest/bin:$PATH
set -x PATH $ANDROID_HOME/platform-tools:$PATH
set -x PATH $ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH
