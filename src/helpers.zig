pub inline fn rdtsc() u64 {
    var eax: u32 = undefined;
    var edx: u32 = undefined;

    asm volatile ("rdtsc"
        : [eax] "={eax}" (eax),
          [edx] "={edx}" (edx),
    );

    return (@as(u64, edx) << 32) | @as(u64, eax);
}
