/* Test-only: keep the generated AIDL binder UNDECLARED so servicemanager does
 * not demand a VINTF entry for the bind-mount HAL test on a build with
 * AXON7_NFC=0. Never installed in an image. */
#include <android/binder_ibinder.h>
void AIBinder_markVintfStability(AIBinder* binder) { (void)binder; }
