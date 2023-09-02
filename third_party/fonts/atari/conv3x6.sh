#! /bin/sh

in=ivo3x6.fon
out=ivo3x6.dat
outinc=ivo3x6.inc

> $out

# Turn 1024 byte font into 576 byte font with 96 glyphs of 6 bytes

for i in `seq 0 95` ; do
    dd if=$in of=$out bs=1 skip=$(($i*8)) count=6 conv=notrunc seek=$(($i*6)) \
        status=none
done

# Generate include file

xxd -c 6 -g 1 -i ivo3x6.dat | head -n -2 | grep -v unsigned | \
    sed 's/,$//g; s/^/    .byte/g; s/0x/$/g' > $outinc
