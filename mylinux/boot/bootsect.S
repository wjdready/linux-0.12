/*
    bootsect.s 将被 BIOS 加载到 0x7c00 地址处，然后它将自己移到 0x90000 地址处执行。
    之后它使用 BIOS 中断将 setup 直接加载到自己的后面 0x90200 处，并将 system 加载到
    0x100000 处

    注意！目前的内核系统最大长度限制为（8*65536）字节（512KB），即使是在将来这也应该没有问题
    的。我想让他保持简单明了。这样512KB的最大内核长度应该足够了，尤其是这里没有像MINIX中
    一样包含缓冲区高速缓冲。
*/


#include <linux/config.h>

SYSSIZE = DEF_SYSSIZE
SETUPLEN = 4                # setup程序占用的扇区数
BOOTSEG  = 0x07c0           # bootsect代码所在内存原始段地址
INITSEG  = DEF_INITSEG      # 将bootsect移到位置0x9000 避开系统模块占用处
SETUPSEG = DEF_SETUPSEG		# setup 程序从内存0x90200处开始
SYSSEG   = DEF_SYSSEG		# system 模块加载到 0x10000 处
ENDSEG   = SYSSEG + SYSSIZE	# 停止加载的段地址

    .code16
    .section .text
    .global _start
    .global disp_str
    .type _start, %function
    .type disp_str, %function
_start:

    # 将 bootsect 代码拷贝到 0x9000 处执行

    mov $BOOTSEG, %ax   # 0x07c0
    mov %ax, %ds

    mov $INITSEG, %ax   # 0x9000
    mov %ax, %es

    mov $256, %cx       # 拷贝 512 字节, ds:si --> es:di
    sub %si, %si
    sub %di, %di
    rep movsw

    ljmp $INITSEG, $_start_size

_start_size = (. - _start)

/* 
    从现在开始，CPU移动到0x90000位置处的代码中执行
*/
go:
    mov %cs, %ax
    mov $(0xff00-0x0c), %dx # 栈地址往后预留12字节来保存参数

    mov %ax, %ds            # 设置 ds = es = ss = cs
    mov %ax, %es

    mov %ax, %ss
    mov %dx, %sp            # 将栈指针偏移到足够远位置 0xff00-0x0c

    # fs = 0, gs = 参数表所在的段值
    push $0
    pop %fs

    mov	$0x78, %bx          # fs:bx 处存放软驱参数表偏移地址
    mov %fs:(%bx), %si      # 将参数表偏移地址加载到 si 作为源地址

    mov %dx, %di            # 设置目的地址, 这里为栈地址
    mov $6, %cx             # 复制 12 字节, gs:si --> es:di
    cld                     # 清方向标志, 复制时指针递增

    rep movsw %gs:(%si), %es:(%di)

    mov %dx, %di
    movb $18, %es:4(%di)    # 修改参数表扇区最大扇区数为18

    mov %fs:(%bx), %di      # di 指向参数表地址
    mov %fs:2(%bx), %es

    mov %cs, %ax            # fs = gs = 0x9000
    mov %ax, %fs
    mov %ax, %gs

    xor %ah, %ah            # reset FDC 软盘控制器
    xor %dl, %dl            # dl = 0, 第一个软驱
    int $0x13

/* 
    以下代码的用途是利用 BIOS 中断 int 0x13 将 setup 模块从磁盘第2个扇区开始读到
    0x90200 开始处，共读4个扇区。在读操作过程中如果读出错，则显示磁盘上出错扇区位置,
    然后复位驱动器并重试,没有退路。

    int 0x13 读扇区使用调用参数设置如下:

    ah = 0x02  读磁盘扇区到内存		al = 需要读出的扇区数量;
    ch = 磁道(柱面)号的低8位;		cl = 开始扇区(位0~5),磁道号高2位(位6~7);
    dh = 磁头号；				   dl = 驱动器号（如果是硬盘则位7要置位;
    es:bx 指向数据缓冲区;	如果出错则CF标志置位,ah中是出错码.
*/

load_setup:
    mov $INITSEG, %ax
    mov %ax, %es

    xor	%dx, %dx            # drive 0, head 0
    mov $0x0002, %cx        # sector 2, track 0
    mov $0x0200, %bx        # address = 512, in INITSEG
    mov $0x0200 + SETUPLEN, %ax # service 2, nr of sectors
    int $0x13
    jnc	ok_load_setup

ok_load_setup:

    mov $mystr, %bx
    call disp_str

    mov $mystr2, %bx
    call disp_str

    jmp ok_load_setup

disp_str:
    push %ax
    push %bx
    push %es
    push %di
    push %si

    push $0xb800
    pop %es

    jmp _start_disp

    # 本地静态变量
    _disp_pos:
    .int 0

    _start_disp:

    # 显示字符串
    mov $0, %si             # 用于字符串地址索引
    mov _disp_pos, %di      # 用于显存地址索引
    mov $0x03, %ah          # 每个字符的显示属性

    disp:
    movb (%bx, %si), %al    # 获取当前索引字符

    cmp $0, %al             # 到达 '\0' 结尾则结束显示
    je _disp_done

    cmp $'\n', %al          # 检测到换行符
    jne _not_new_line

    push %ax                # 进行换行
    mov _disp_pos, %ax
    add $80*2, %ax

    cmp $80*2*25, %ax       # 换行后显示超过屏幕区域
    jne _skip_reset
    mov $0, %ax
    
    _skip_reset:
    mov %ax, _disp_pos
    mov %ax, %di
    pop %ax

    jmp _continue_dsip

    _not_new_line:
    mov %ax, %es:(%di)      # 复制到显存, 源操作数 ax, 复制的是 16 位
    _continue_dsip:
    add $2, %di             # 一次复制2个字节, 包括显示属性字节, 显存索引 + 2  
    inc %si                 # 字符串索引 + 1
    jmp disp

    _disp_done:

    pop %si
    pop %di
    pop %es
    pop %bx
    pop %ax

    ret

mystr:
    .asciz  "Hello, World! MyLinux\n"
mystr2:
    .asciz  "Good person\n\n"
    str_len = (. - mystr)

    .section .boot_end,"a"
    .word 0xaa55

sector2:
    .asciz  "sector2\n"
    .fill 512 - (. - sector2), 1, 0

sector3:
    .asciz  "sector3\n"
    .fill 512 - (. - sector3), 1, 0

sector4:
    .asciz  "sector4\n"
    .fill 512 - (. - sector4), 1, 0

sector5:
    .asciz  "sector5\n"
    .fill 512 - (. - sector5), 1, 0
