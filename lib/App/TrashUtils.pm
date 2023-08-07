package App::TrashUtils;

use 5.010001;
use strict;
use warnings;
use Log::ger;

# AUTHORITY
# DATE
# DIST
# VERSION

our %SPEC;

sub _complete_trashed_filenames {
    require Complete::Util;
    require File::Trash::FreeDesktop;

    my %args = @_;
    my $word = $args{word} // '';

    my $trash = File::Trash::FreeDesktop->new;
    my @ct = $trash->list_contents;

    if ($word =~ m!/!) {
        # if word contains '/', then we complete with trashed files' paths
        Complete::Util::complete_array_elem(array=>[map { $_->{path} } @ct], word=>$word);
    } else {
        # otherwise we complete with trashed files' filenames
        Complete::Util::complete_array_elem(array=>[map { my $filename = $_->{path}; $filename =~ s!.+/!!; $filename } @ct], word=>$word);
    }
}

$SPEC{trash_list} = {
    v => 1.1,
    summary => 'List contents of trash directories',
    args => {
        detail => {
            schema => 'bool*',
            cmdline_aliases => {l=>{}},
        },
        wildcard => {
            summary => 'Filter path or filename with wildcard pattern',
            description => <<'_',

Will be matched against path if pattern contains `/`, otherwise will be matched
against filename. Supported patterns are jokers (`*` and `?`), character class
(e.g. `[123]`), and globstar (`**`).

When specifying the wildcard on the CLI, remember to quote it to protect from
being interpreted by the shell, e.g. to match files in the current directory.

_
            schema => 'str*',
            pos => 0,
            completion => \&_complete_trashed_filenames,
        },
    },
    examples => [
        {
            summary => 'List all files in trash cans',
            argv => [],
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'List files ending in ".pm" in trash cans, show details',
            argv => ['-l', '*.pm'],
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'List all files under the path "/home/ujang/Documents" in trash cans',
            argv => ['/home/ujang/Documents/**'],
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],
};
sub trash_list {
    require File::Trash::FreeDesktop;

    my %args = @_;

    my %opts;
    if (defined $args{wildcard}) {
        if ($args{wildcard} =~ m!/!) {
            $opts{path_wildcard} = $args{wildcard};
        } else {
            $opts{filename_wildcard} = $args{wildcard};
        }
    }

    my @contents = File::Trash::FreeDesktop->new->list_contents(\%opts);
    if ($args{detail}) {
        [200, "OK", \@contents, {
            'table.fields' => [qw/path deletion_date/],
            'table.field_formats' => [undef, 'iso8601_datetime'],
        }];
    } else {
        [200, "OK", [map {$_->{path}} @contents]];
    }
}

$SPEC{trash_list_trashes} = {
    v => 1.1,
    summary => 'List trash directories',
    args => {
        home_only => {
            schema => 'bool*',
        },
    },
};
sub trash_list_trashes {
    require File::Trash::FreeDesktop;

    my %args = @_;

    my @trashes = File::Trash::FreeDesktop->new(
        home_only => $args{home_only},
    )->list_trashes;
    [200, "OK", \@trashes];
}

$SPEC{trash_put} = {
    v => 1.1,
    summary => 'Put files into trash',
    args => {
        files => {
            'x.name.is_plural' => 1,
            'x.name.singular' => 'file',
            schema => ['array*', of=>'pathname*'],
            req => 1,
            pos => 0,
            slurpy => 1,
        },
    },
    features => {
        dry_run => 1,
    },
    examples => [
        {
            summary => 'Trash two files',
            argv => ['file1', 'file2.txt'],
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],
};
sub trash_put {
    require File::Trash::FreeDesktop;
    require Perinci::Object::EnvResultMulti;

    my %args = @_;

    my $trash = File::Trash::FreeDesktop->new;
    my $res = Perinci::Object::EnvResultMulti->new;
    for my $file (@{ $args{files} }) {
        my @st = lstat $file;
        if (!(-e _)) {
            $res->add_result(404, "File not found: $file", {item_id=>$file});
            next;
        }
        if ($args{-dry_run}) {
        log_info "[DRY_RUN] Trashing %s ...", $file;
            $res->add_result(200, "Trashed (DRY_RUN)", {item_id=>$file});
            next;
        }
        log_info "Trashing %s ...", $file;
        eval { $trash->trash($file) };
        if ($@) {
            $res->add_result(500, "Can't trash: $file: $@", {item_id=>$file});
            next;
        }
        $res->add_result(200, "Trashed", {item_id=>$file});
    }
    $res->as_struct;
}

$SPEC{trash_rm} = {
    v => 1.1,
    summary => 'Permanently remove files in trash',
    args => {
        files => {
            'x.name.is_plural' => 1,
            'x.name.singular' => 'file',
            summary => 'Wildcard pattern will be interpreted (unless when --no-wildcard option is specified)',
            schema => ['array*', of=>'str*'],
            req => 1,
            pos => 0,
            slurpy => 1,
            element_completion => \&_complete_trashed_filenames,
        },
        no_wildcard => {
            schema => 'true*',
            cmdline_aliases => {W=>{}},
        },
    },
    features => {
        dry_run => 1,
    },
    examples => [
        {
            summary => 'Permanently remove files named "f1" and "f2" in trash',
            argv => ['f1', 'f2'],
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'Permanently remove all .pl and .pm files in trash',
            argv => ['*.pl', '*.pm'],
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],
};
sub trash_rm {
    require File::Trash::FreeDesktop;
    require String::Wildcard::Bash;

    my %args = @_;

    my $trash = File::Trash::FreeDesktop->new;
    for my $file (@{ $args{files} }) {
        my $opts = {};
        if (!$args{no_wildcard} && String::Wildcard::Bash::contains_wildcard($file)) {
            if ($file =~ m!/!) {
                $opts->{path_wildcard} = $file;
            } else {
                $opts->{filename_wildcard} = $file;
            }
        } else {
            if ($file =~ m!/!) {
                $opts->{path} = $file;
            } else {
                $opts->{filename} = $file;
            }
        }

        if ($args{-dry_run}) {
            log_info "Listing files in trash: %s", $opts;
            my @ct = $trash->list_contents($opts);
            for my $e (@ct) {
                log_info "[DRY_RUN] Permanently removing path: %s ...", $e->{path};
            }
        } else {
            log_info "Permanently removing: %s ...", $opts;
            $trash->erase($opts);
        }
    }
    [200, "OK"];
}

$SPEC{trash_restore} = {
    v => 1.1,
    summary => 'Put trashed files back into their original path',
    args => {
        files => {
            'x.name.is_plural' => 1,
            'x.name.singular' => 'file',
            summary => 'Wildcard pattern will be interpreted (unless when --no-wildcard option is specified)',
            schema => ['array*', of=>'str*'],
            req => 1,
            pos => 0,
            slurpy => 1,
            element_completion => \&_complete_trashed_filenames,
        },
        no_wildcard => {
            schema => 'true*',
            cmdline_aliases => {W=>{}},
        },
    },
    features => {
        dry_run => 1,
    },
    examples => [
        {
            summary => 'Restore two files named "f1" and "f2" from trash',
            argv => ['f1', 'f2'],
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'Restore all .pl and .pm files from trash',
            argv => ['*.pl', '*.pm'],
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],
};
sub trash_restore {
    require File::Trash::FreeDesktop;
    require String::Wildcard::Bash;

    my %args = @_;

    my $trash = File::Trash::FreeDesktop->new;
    for my $file (@{ $args{files} }) {
        my $opts = {};
        if (!$args{no_wildcard} && String::Wildcard::Bash::contains_wildcard($file)) {
            if ($file =~ m!/!) {
                $opts->{path_wildcard} = $file;
            } else {
                $opts->{filename_wildcard} = $file;
            }
        } else {
            if ($file =~ m!/!) {
                $opts->{path} = $file;
            } else {
                $opts->{filename} = $file;
            }
        }

        if ($args{-dry_run}) {
            log_info "Listing files in trash: %s", $opts;
            my @ct = $trash->list_contents($opts);
            for my $e (@ct) {
                log_info "[DRY_RUN] Restoring path: %s ...", $e->{path};
            }
        } else {
            log_info "Restoring: %s ...", $opts;
            $trash->recover($opts);
        }
    }
    [200, "OK"];
}

1;
#ABSTRACT: Utilities related to desktop trash

=head1 DESCRIPTION

This distributions provides the following command-line utilities:

# INSERT_EXECS_LIST

Prior to C<App::TrashUtils>, there is already C<trash-cli> [1] which is written
in Python. App::TrashUtils aims to scratch some itches and offers some
enhancements:

=over

=item * trash-restore accepts multiple arguments

=item * trash-list accepts files/wildcard patterns

=item * dry-run mode

=item * tab completion

=item * written in Perl

Lastly, App::TrashUtils is written in Perl and is easier to hack for Perl
programmers.

=back


=head1 SEE ALSO

[1] L<https://github.com/andreafrancia/trash-cli>, Python-based CLIs delated to
desktop trash.

L<File::Trash::FreeDesktop>

Alternative CLI's: L<trash-u> (from L<App::trash::u>) which supports undo.

=cut
