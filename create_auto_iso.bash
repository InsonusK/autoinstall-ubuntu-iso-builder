#!/bin/bash
set -e

# Проверка аргументов
if [ $# -ne 3 ]; then
    echo "Usage: $0 <name> <path_to_iso> <path_to_autoinstall_yaml>"
    exit 1
fi
ISO_PATH=$2
AUTO_ISO_NAME=$1

ISO_NAME=$(basename "$ISO_PATH")
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
AUTO_INSTALL_YAML_PATH=$3

AUTO_ISO_TMP_DIR_NAME=$(echo "$AUTO_ISO_NAME" | sed 's/[-.]/_/g')
TMP_PATH="${ROOT_DIR}/tmp/${AUTO_ISO_TMP_DIR_NAME}"
NEW_ISO_FOLDER_PATH="${TMP_PATH}/source-files"

echo "===Создаем директорию где будем создавать диск с автоустановкой==="
if [ -d $TMP_PATH ]; then
    rm -r $TMP_PATH
fi
mkdir -p $TMP_PATH

echo "===Распаковываем ISO==="
# 7z --help
# ...
# -o{Directory} : set Output directory -> -osource-files приведет к выгрузке содержимого iso в директорию source-files
# ...
7z -y x "$ISO_PATH" -osource-files
if [ $? -ne 0 ]; then
    echo "Error unpacking ISO. Exiting."
    exit 1
fi
mv "source-files" "${NEW_ISO_FOLDER_PATH}/"

echo "===Переносим [BOOT] из source-files, убирая [ ] (для убодства)"
mv "${TMP_PATH}/source-files/[BOOT]" "${TMP_PATH}/BOOT"

echo "===Копируем autoinstall.yaml==="
mkdir -p "${NEW_ISO_FOLDER_PATH}/nocloud"
touch "${NEW_ISO_FOLDER_PATH}/nocloud/meta-data"
cp $AUTO_INSTALL_YAML_PATH "${NEW_ISO_FOLDER_PATH}/nocloud/user-data"

echo "===Копируем grub.cfg в нужное место==="
if [ -f "${ROOT_DIR}/config/grub.cfg" ]; then
    cp "${ROOT_DIR}/config/grub.cfg" "${NEW_ISO_FOLDER_PATH}/boot/grub/grub.cfg"
else
    echo "grub.cfg not found, skipping grub configuration"
fi

echo "===Создаем команду сборки ${AUTO_ISO_NAME}.iso==="
BUILD_SCRIPT_PATH="${TMP_PATH}/build_autoinstall_iso.tmp.bash"
SCRIPT_PATH="${TMP_PATH}/build_autoinstall_iso.bash"
xorriso -indev $ISO_PATH -report_el_torito as_mkisofs > "${BUILD_SCRIPT_PATH}"

# Шаги 1-6: Редактируем файл
{
    # Добавляем строку xorriso -as mkisofs -r в начало файла
    echo "xorriso -as mkisofs -r \\"
    echo "-o autoinstall-ubuntu.iso \\"
    # Читаем оригинальный скрипт построчно
    while IFS= read -r line; do
        # После строки `-V 'Ubuntu-Server 24.10 amd64'` добавляем `-o autoinstall-ubuntu.iso`
        if [[ "$line" == *"--grub2-mbr"* ]]; then
            # Убираем `--interval:local_fs:0s-15s:zero_mbrpt,zero_gpt:'ubuntu-24.10-live-server-amd64.iso'`
            echo "--grub2-mbr BOOT/1-Boot-NoEmul.img \\"
        elif [[ "$line" == -append_partition* ]]; then
            # Убираем все после `--` и добавляем `BOOT/2-Boot-NoEmul.img \\`
            echo "$line" | sed 's/ --.*//g' | sed 's/$/ BOOT\/2-Boot-NoEmul.img \\/'
        else
            # Для остальных строк добавляем `\\` в конце
            echo "$line \\"
        fi
    done < "$BUILD_SCRIPT_PATH"
    echo "source-files"
} > "$SCRIPT_PATH"

echo "===Запускаем сборку ${AUTO_ISO_NAME}.iso==="
pushd $TMP_PATH > /dev/null
bash $SCRIPT_PATH
popd > /dev/null

echo "===Перемещаяем autoinstall-ubuntu.iso==="
echo "tmp/${AUTO_ISO_TMP_DIR_NAME}/autoinstall-ubuntu.iso > result/${AUTO_ISO_NAME}.iso"
mv "${TMP_PATH}/autoinstall-ubuntu.iso" "${ROOT_DIR}/result/${AUTO_ISO_NAME}.iso"