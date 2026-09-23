# SPDX-License-Identifier: Apache-2.0

use Mojo::Base 'basetest', -signatures;
use testapi;

sub run ($self) {
    # The converter appends ttyS0 to the candidate's kernel command line. These
    # checkpoints distinguish firmware/boot-loader stalls from a kernel or
    # early-userspace failure without assuming an interactive guest transport.
    my $ansi_sgr = qr/\e\[[0-9;]*m/;
    # The CI QEMU has no NVIDIA device. The upstream CDI refresh unit therefore
    # exits there, while the rest of the composed image keeps booting. The
    # console decorates its status line with SGR codes and can truncate the unit
    # name with an ellipsis, so recognize exactly that rendered unit. Every
    # other failed service remains fatal.
    my $qemu_no_gpu_service = qr/
        (?:$ansi_sgr)*
        nvidia-cdi-refresh
        (?:[.]service)?
        (?=[[:space:]]|$ansi_sgr|[^\x00-\x7f]|$)
    /ix;
    my $fatal = qr/(?:
        Kernel[ ]panic[ ]-[ ]not[ ]syncing |
        BUG: |
        Oops: |
        general[ ]protection[ ]fault |
        Unable[ ]to[ ]handle[ ]kernel |
        Entering[ ]emergency[ ]mode |
        Failed[ ]to[ ]mount |
        Dependency[ ]failed[ ]for |
        Failed[ ]to[ ]start[ ](?!$qemu_no_gpu_service)
    )/ix;
    my $boot_complete = qr/(?:
        (?:^|[\n]).{0,160}login:[[:space:]]*$ |
        Reached[ ]target[ ].*?(?:Graphical[ ]Interface|Multi-User[ ]System) |
        Started[ ].*Display[ ]Manager |
        Started[ ]Serial[ ]Getty[ ]on[ ]ttyS0
    )/imx;

    # wait_serial accepts one regular expression. Pair each required marker
    # with the fatal expression so a panic/oops/emergency condition fails at
    # the point it appears rather than being mislabeled as a later timeout.
    my $kernel = wait_serial(qr/(?:$fatal|Linux[ ]version[ ])/, timeout => 180);
    die 'Doors boot gate did not observe a Linux kernel on ttyS0' unless defined $kernel;
    die "Doors boot gate observed a kernel failure:\n${kernel}" if $kernel =~ $fatal;

    my $systemd = wait_serial(qr/(?:$fatal|systemd[[]1[]]:)/, timeout => 300);
    die 'Doors boot gate did not observe systemd PID 1 on ttyS0' unless defined $systemd;
    die "Doors boot gate observed an early-runtime failure:\n${systemd}" if $systemd =~ $fatal;

    # The serial buffer is read-only by design; do not send a login command.
    my $boot = wait_serial(qr/(?:$fatal|$boot_complete)/, timeout => 900);
    die 'Doors boot gate timed out before the serial boot-complete marker' unless defined $boot;
    die "Doors boot gate observed an early-runtime failure:\n${boot}" if $boot =~ $fatal;

    record_info(
        'serial boot complete',
        'Observed the composed image kernel, systemd PID 1, and a serial login or boot target marker.',
    );

    # Keep observing after readiness so a late panic, oops, emergency target,
    # mount failure, dependency failure, or failed service cannot be hidden by
    # the first successful login prompt. With expect_not_found, wait_serial
    # returns the unmatched serial text after a quiet timeout and undef when
    # the forbidden expression appears during the bounded observation window.
    my $fatal_after_boot = wait_serial($fatal, timeout => 90, expect_not_found => 1);
    die 'Doors boot gate observed a fatal serial signature after boot completion' unless defined $fatal_after_boot;
}

1;
