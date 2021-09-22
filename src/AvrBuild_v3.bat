@ECHO OFF
"c:\Program Files (x86)\Atmel\Studio\7.0\toolchain\avr8\avrassembler\avrasm2.exe" -S "labels.tmp" -fI -W+ie -C V2 -o "vibrotimer_v3.hex" -d "vibrotimer_v3.obj" -e "vibrotimer_v3.eep" -m "vibrotimer_v3.map" "vibrotimer_v3.asm"
