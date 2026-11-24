#!/usr/bin/env python3
import os
import re
import shutil

def patch_build_gradle():
    kts_path = "android/app/build.gradle.kts"
    groovy_path = "android/app/build.gradle"

    if os.path.exists(kts_path):
        with open(kts_path, "r", encoding="utf-8") as f:
            content = f.read()

        # Ensure compileSdk = 35
        content = re.sub(r"compileSdk\s*=\s*\S+", "compileSdk = 35", content)
        # Ensure minSdk = 24
        content = re.sub(r"minSdk\s*=\s*\S+", "minSdk = 24", content)
        # Ensure coreLibraryDesugaringEnabled in compileOptions
        if "isCoreLibraryDesugaringEnabled" not in content:
            content = content.replace(
                "compileOptions {",
                "compileOptions {\n        isCoreLibraryDesugaringEnabled = true",
                1
            )
        # Add desugar_jdk_libs dependency
        if "desugar_jdk_libs" not in content:
            if "dependencies {" in content:
                content = content.replace(
                    "dependencies {",
                    'dependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")',
                    1
                )
            else:
                content += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'

        with open(kts_path, "w", encoding="utf-8") as f:
            f.write(content)
        print("Patched android/app/build.gradle.kts successfully.")

    elif os.path.exists(groovy_path):
        with open(groovy_path, "r", encoding="utf-8") as f:
            content = f.read()

        content = re.sub(r"compileSdk\s*=\s*\S+", "compileSdk = 35", content)
        content = re.sub(r"compileSdkVersion\s+\S+", "compileSdkVersion 35", content)
        content = re.sub(r"minSdk\s*=\s*\S+", "minSdk = 24", content)
        content = re.sub(r"minSdkVersion\s+\S+", "minSdkVersion 24", content)

        if "coreLibraryDesugaringEnabled" not in content:
            content = content.replace(
                "compileOptions {",
                "compileOptions {\n        coreLibraryDesugaringEnabled true",
                1
            )
        if "desugar_jdk_libs" not in content:
            if "dependencies {" in content:
                content = content.replace(
                    "dependencies {",
                    "dependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'",
                    1
                )
            else:
                content += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"

        with open(groovy_path, "w", encoding="utf-8") as f:
            f.write(content)
        print("Patched android/app/build.gradle successfully.")
    else:
        raise FileNotFoundError("Neither build.gradle.kts nor build.gradle found!")


def patch_manifest():
    manifest_path = "android/app/src/main/AndroidManifest.xml"
    with open(manifest_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Set Korean app display name
    content = re.sub(r'android:label="[^"]*"', 'android:label="냉장고를 부탁해"', content, count=1)

    permissions = [
        "android.permission.INTERNET",
        "android.permission.CAMERA",
        "android.permission.POST_NOTIFICATIONS",
        "android.permission.RECEIVE_BOOT_COMPLETED",
        "android.permission.VIBRATE",
        "android.permission.SCHEDULE_EXACT_ALARM",
    ]
    perm_block = ""
    for p in permissions:
        if p not in content:
            perm_block += f'    <uses-permission android:name="{p}"/>\n'

    if perm_block:
        content = content.replace("<application", perm_block + "    <application", 1)

    receivers_block = '''
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
    </application>'''

    if "ScheduledNotificationReceiver" not in content:
        content = content.replace("</application>", receivers_block, 1)

    with open(manifest_path, "w", encoding="utf-8") as f:
        f.write(content)
    print("Patched AndroidManifest.xml successfully.")


def copy_icons():
    densities = ["mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi"]
    for d in densities:
        src = f"assets/icons/ic_launcher_{d}.png"
        dst_dir = f"android/app/src/main/res/mipmap-{d}"
        if os.path.exists(src):
            os.makedirs(dst_dir, exist_ok=True)
            shutil.copy2(src, os.path.join(dst_dir, "ic_launcher.png"))
    print("Copied Android launcher icons successfully.")


if __name__ == "__main__":
    patch_build_gradle()
    patch_manifest()
    copy_icons()
