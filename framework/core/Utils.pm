#-------------------------------------------------------------------------------
# Copyright (c) 2014-2015 René Just, Darioush Jalali, and Defects4J contributors.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#-------------------------------------------------------------------------------

=pod

=head1 NAME

Utils.pm -- Provides helper functions.

=head1 DESCRIPTION

This module provides general helper functions such as parsing config or data files.

=cut
package Utils;

use warnings;
use strict;

use File::Basename;
use Cwd qw(abs_path);
use Carp qw(confess);

use Constants;

my $dir = dirname(abs_path(__FILE__));

=pod

=head1 HELPER FUNCTIONS:

=over 4

=item B<get_tmp_dir> C<get_tmp_dir([tmp_root])>

Returns the path to a unique (local) temporary directory:
B<"tmp_root"/"script_name"_"process_id"_"timestamp">

The path is unique w.r.t. a local file system. The root directory to be used can
be specified with C<tmp_root> (optional) -- the default is F</tmp>.

=cut
sub get_tmp_dir {
    my $tmp_root = shift // "/tmp";
    return "$tmp_root/" . basename($0) . "_" . $$ . "_" . time;
}

=pod

=item B<get_abs_path> C<get_abs_path(dir)>

Returns the absolute path to the directory F<dir>.

=cut
sub get_abs_path {
    @_ == 1 or die $ARG_ERROR;
    my $dir = shift;
    # Remove trailing slash
    $dir =~ s/^(.+)\/$/$1/;
    return abs_path($dir);
}

=pod


=pod

=item B<get_failing_tests> C<get_failing_tests(test_result_file)>

Returns a reference to a hash of references to lists with failing test classes
and methods found in F<test_result_file>. The F<test_result_file> may contain
arbitrary lines -- this method only considers lines that match the pattern:
B</--- ([^:]+)(::([^:]+))?/>.

The data structure of the returned hash reference looks like:

{classes} => [org.foo.Class1 org.bar.Class2]

{methods} => [org.foo.Class3::method1 org.foo.Class3::method2]

=cut
sub get_failing_tests {
    @_ == 1 or die $ARG_ERROR;
    my $file_name = shift;

    my $list = {
        classes => [],
        methods => []
    };
    open FILE, $file_name or die "Cannot open test result file ($file_name): $!";
    while (<FILE>) {
        chomp;
        /--- ([^:]+)(::([^:]+))?/ or next;
        my $class = $1;
        my $method= $3;
        if (defined $method) {
            push(@{$list->{methods}}, "${class}::$method");
        } else {
            push(@{$list->{classes}}, $class);
        }
    }
    close FILE;
    return $list;
}

=pod

=item B<has_failing_tests> C<has_failing_tests(result_file)>

Returns 1 if the provided F<result_file> lists any failing test classes or
failing test methods. Returns 0 otherwise.

=cut
sub has_failing_tests {
    @_ == 1 or die $ARG_ERROR;
    my $file_name = shift;

    my $list = get_failing_tests($file_name) or die "Could not parse file";
    my @fail_methods = @{$list->{methods}};
    my @fail_classes = @{$list->{classes}};

    return 1 unless (scalar(@fail_methods) + scalar(@fail_classes)) == 0;

    return 0;
}

=pod

=item B<write_config_file> C<write_config_file(filename, config_hash)>

Writes all key-value pairs of C<config_hash> to a config file named
C<filename>. Existing entries are overridden and missing entries are added
to the config file -- all existing but unmodified entries are preserved.

=cut
sub write_config_file {
    @_ == 2 or die $ARG_ERROR;
    my ($file, $hash) = @_;
    my %newconf = %{$hash};
    if (-e $file) {
        my $oldconf = read_config_file($file);
        for my $key (keys %{$oldconf}) {
            $newconf{$key} = $oldconf->{$key} unless defined $newconf{$key};
        }
    }
    open(OUT, ">$file") or die "Cannot create config file ($file): $!";
    print(OUT "#File automatically generated by Defects4J\n");
    for my $key(keys(%newconf)) {
        print(OUT "$key=$newconf{$key}\n");
    }
    close(OUT);
}

=pod

=item B<read_config_file> C<read_config_file(filename)>

Read all key-value pairs of the config file C<filename>. Format: key=value.
Returns a hash containing all key-value pairs on success, undef otherwise.

=cut
sub read_config_file {
    @_ == 1 or die $ARG_ERROR;
    my $file = shift;
    if (!open(IN, "<$file")) {
        print(STDERR "Cannot open config file ($file): $!\n");
        return undef;
    }
    my $hash = {};
    while(<IN>) {
        # Skip comments and empty lines
        next if /^\s*#/;
        next if /^\s*$/;
        chomp;
        # Read key value pair and remove white spaces
        my ($key, $val) = split /=/;
        $key =~ s/ //;
        $val =~ s/ //;
        $hash->{$key} = $val;
    }
    close(IN);
    return $hash;
}

=pod

=item B<check_vid> C<check_vid(vid)>

Check whether C<vid> represents a valid version id, i.e., matches \d+[bf].

=cut
sub check_vid {
    @_ == 1 or die $ARG_ERROR;
    my $vid = shift;
    $vid =~ /^(\d+)([bf])$/ or confess("Wrong version_id: $vid -- expected \\d+[bf]!");
    return {valid => 1, bid => $1, type => $2};
}

=pod

=item B<tag_prefix> C<tag_prefix(pid, vid)>

Returns the Defects4J prefix for a git tag, given project and version id.

=cut
sub tag_prefix {
    @_ == 2 or die $ARG_ERROR;
    my ($pid, $vid) = @_;
    my $bid = check_vid($vid)->{bid};
    return "D4J_" . $pid . "_" . $bid . "_";
}

=pod

=item B<exec_cmd> C<exec_cmd(cmd, description)>

Runs a system command and indicates whether it succeeded or failed. This
subroutine captures the output (B<stdout>) of the command and logs the output to
B<stderr> only if the command fails or if C<Constants::DEBUG> is set to true.
This subroutine also converts exit codes into boolean values, i.e., it returns
B<1> if the command succeeded and B<0> otherwise.

=back

=cut
sub exec_cmd {
    @_ == 2 or die $ARG_ERROR;
    my ($cmd, $descr) = @_;
    print(STDERR "$descr ... ");
    my $log = `$cmd`; my $ret = $?;
    if ($ret!=0) {
        print("FAIL\n$log");
        return 0;
    }
    print(STDERR "OK\n");
    # Upon success, only print log messages if debugging is enabled
    print(STDERR $log) if $DEBUG;

    return 1;
}

1;
