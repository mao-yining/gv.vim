vim9script
# Maintainer:     Mao-Yining <mao.yining@outlook.com>
# Last Modified:  2025-12-20

import autoload "../autoload/gv.vim"

command! -bang -nargs=* -range=0 -complete=customlist,fugitive#LogComplete GV gv.GV(<bang>0, <count>, <line1>, <line2>, <q-args>)
