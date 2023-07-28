package App::TrashUtils;

use 5.010001;
use strict;
use warnings;

# AUTHORITY
# DATE
# DIST
# VERSION

our %SPEC;

$SPEC{trash_list} = {
    v => 1.1,
    summary => 'List contents of trash directories',
    args => {
    },
};
sub trash_list {
    require File::Trash::FreeDesktop;

    [200, "OK", [File::Trash::FreeDesktop->new->list_contents]];
}

1;
#ABSTRACT: Utilities related to desktop trash

=head1 DESCRIPTION

This distributions provides the following command-line utilities:

# INSERT_EXECS_LIST


=head1 SEE ALSO

L<File::Trash::FreeDesktop>

=cut
