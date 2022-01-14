use strict;
use warnings;
use autodie;

use Data::Dumper;
use File::Basename;
use File::stat;
use Path::Tiny;

print "Hello World!\n";

### READ CONFIG ###

# my $config = path($ENV{"HOME"}, ".clean_files");
my $config_path = path(".clean_files");
my %config = ();

open (_FH, $config_path) or die "Unable to open config file: $!";
while (<_FH>) {
    chomp;                  # no newline
    s/#.*//;                # no comments
    s/^\s+//;               # no leading white
    s/\s+$//;               # no trailing white
    next unless length;     # anything left?
    my ($var, $value) = split(/\s*=\s*/, $_, 2);
    if ($var eq 'TEMPORARY') {
        $config{$var} = [split(',', $value)];
    } else {
        $config{$var} = $value;
    }
}
close _FH;
print Dumper(%config);

### INITIALIZE MAIN VARIABLES ###

my @files = ();
my $origin_dir = path($config{ORIGIN_DIR});
my $data_dir = path($config{DATA_DIR});

### INITIALIZE SUBROUTINES ###

# [
#     {
#         name: string,
#         path: string,
#         content: string,
#         attributes: int,
#         date: int,
#         suggestions: [
#             {
#                 type: int,
#                 TODO XD
#             }
#         ]
#     }
# ]

sub ls {
    foreach (@_) {
        my $iter = $_->iterator;
        while (my $file = $iter->()) {
            if ($file->is_dir()) {
                ls($file);
            } else {
                push @files, {
                    "name", basename($file),
                    "path", $file->stringify(),
                    "content", $file->slurp_utf8(),
                    "attributes", stat($file)->mode & 0777, # this will show in decimal when printed
                    "date", stat($file)->mtime,
                    "suggestions", ()
                };
            }
        }
    }
}

sub find_same_content {
    foreach my $file1 (@_) {
        foreach my $file2 (@_) {
            next if $file1->{path} eq $file2->{path};
            if ($file1->{content} eq $file2->{content}) {
                push @{$file1->{suggestions}}, {
                    "type", 1,
                    "path", $file2->{path}
                }
            }
        }
    }
}

sub find_empty_content {
    foreach my $file1 (@_) {
        if (($file1->{content}) eq '') {
            push @{$file1->{suggestions}}, {
                "type", 2
            }
        }
    }
}

sub find_new_versions {
    foreach my $file1 (@_) {
        foreach my $file2 (@_) {
            next if $file1->{path} eq $file2->{path};
            if ($file1->{name} eq $file2->{name}) {
                if ($file1->{date} < $file2->{date}) {
                    push @{$file1->{suggestions}}, {
                        "type", 3,
                        "path", $file2->{path}
                    }
                }
            }
        }
    }
}

sub find_temporary {
    foreach my $file1 (@_) {
        foreach (@{$config{TEMPORARY}}) {
            if ($file1->{name} =~ /\Q$_\E\z/) {
                push @{$file1->{suggestions}}, {
                    "type", 4
                }
            }
        }
    }
}

### RUN ###

ls($data_dir);

find_same_content(@files);
find_empty_content(@files);
find_new_versions(@files);
find_temporary(@files);

foreach (@files) {
    print Dumper($_), "\n";
}

# TODO: origin_dir should have all the files
# TODO: suggestion to user - delete all copies: files that have the same content as another, and have a later creation date
# TODO: suggestion to user - delete all empty and temporary (?) files
# TODO: suggestion to user - in case of the same file name, suggest keeping only the newer one
# TODO: suggestion to user - standarize file attributes, for example: rw-r–r–,
# TODO: suggestion to user - change file name in case it contains restricted signs (for example ’:’, ’”’, ’.’, ’;’, ’*’, ’?’, ’$’, ’#’, ’‘’, ’|’, ’\’, ...) and replace them with a common substitute (for example ’_’)

# TODO: Script should be able to find:
#           files containing identical content (and they don't have to have the same name or path)
#           empty files
#           newer file versions with identical names (and they don't have to be in the same path)
#           temporary files (* ̃, *.tmp, and other extensions defined by user)
#           files with "unusual" attributes, for example: rwxrwxrwx
#           files containing restricted signs

# TODO: For each found file, the script should suggest an action:
#           moving / coping to an "apriopate" location in the origin_dir
#           deletion of duplicate / empty file / temporary file
#           replacement of the old version with the new one
#           replacement of the new version with the old one (if the contents are identical)
#           changement of attributes
#           renaming
#           leaving the file unchanged

# NOTE: The script doesn't have to this all at once
# NOTE: Script have to be "resillient" to any signs in files and directories

# TODO: Parameters in config:
#           suggestes attributes value, for example: rw-r–r–
#           set of signs that are considered restricted
#           the sign that is the replacement for restricted signs
#           set of extensions that are considered temporary
