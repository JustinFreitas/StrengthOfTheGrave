:: Assumes running from StrengthOfTheGrave\build
mkdir out\StrengthOfTheGrave
copy ..\extension.xml out\StrengthOfTheGrave\
copy ..\readme.txt out\StrengthOfTheGrave\
copy ..\"Open Gaming License v1.0a.txt" out\StrengthOfTheGrave\
mkdir out\StrengthOfTheGrave\graphics\icons
copy ..\graphics\icons\strengthofthegrave_icon.png out\StrengthOfTheGrave\graphics\icons\
copy ..\graphics\icons\white_strengthofthegrave_icon.png out\StrengthOfTheGrave\graphics\icons\
mkdir out\StrengthOfTheGrave\campaign
copy ..\campaign\ct_host.xml out\StrengthOfTheGrave\campaign\
mkdir out\StrengthOfTheGrave\scripts
copy ..\scripts\strengthofthegrave.lua out\StrengthOfTheGrave\scripts\
copy ..\scripts\ct_host_ct_entry.lua out\StrengthOfTheGrave\scripts\
cd out
CALL ..\zip-items StrengthOfTheGrave
rmdir /S /Q StrengthOfTheGrave\
copy StrengthOfTheGrave.zip StrengthOfTheGrave.ext
cd ..
explorer .\out
