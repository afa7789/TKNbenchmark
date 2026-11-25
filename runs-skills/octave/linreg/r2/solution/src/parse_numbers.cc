// parse_numbers: fast whitespace-separated number parser for linreg.
#include <octave/oct.h>

#include <cstdlib>
#include <vector>

DEFUN_DLD (parse_numbers, args, ,
           "-*- texinfo -*-\n\
@deftypefn {} {@var{v} =} parse_numbers (@var{text})\n\
Parse whitespace-separated decimal numbers in the char row @var{text}\n\
into a column vector.  Parsing stops at the first unparsable token.\n\
@end deftypefn")
{
  if (args.length () != 1 || ! args(0).is_string ())
    print_usage ();

  const charNDArray chars = args(0).char_array_value ();
  const octave_idx_type len = chars.numel ();
  std::string buf (chars.data (), len);   // NUL-terminated copy for strtod

  std::vector<double> vals;
  vals.reserve (len / 4 + 1);

  const char *p = buf.c_str ();
  const char *end = p + len;
  while (p < end)
    {
      char *next;
      const double x = std::strtod (p, &next);
      if (next == p)
        break;
      vals.push_back (x);
      p = next;
    }

  ColumnVector out (vals.size ());
  std::copy (vals.begin (), vals.end (), out.fortran_vec ());
  return ovl (out);
}
