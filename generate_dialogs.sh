pwd
cd star-wars-analysis
python3 swa.py cvrt "(\$partId,\$1,\$2,'\$4')" --sql-escape --rt -f 1 2 3 -c QUI-GON=0 PALPATINE=1 ANAKIN=2 OBI-WAN=3 "COUNT DOOKU=4" "DARTH MAUL=5" PADME=6 YODA=7 "MACE WINDU=8" "GENERAL GRIEVOUS=9" VADER=2 > "../dialoge.txt"
