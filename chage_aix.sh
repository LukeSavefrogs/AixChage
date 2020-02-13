#!/usr/bin/ksh
# Original: GioIan     25/05/2017 - aix_chage
# Edit:     Salvarani  30/01/2020 - Added several attributes (Password inactive, Account expires, 
#                                       Minimum/Maximum number of days between password change, Number of days of warning before password expires), 
#                                       changed date output format and removed username print
# Edit:     Salvarani  13/02/2020 - Changed structure to a C-Like structure, optimized and reviewed code, added check for dependencies

# Global Variables
red='\033[0;31m';
green='\033[0;32m';
yellow='\033[0;33m';
default='\033[0m';


# Main function: 
#       C-style Program Entry Point, retrieves and display data
# 
main () {
    # Check if crucial programs are installed
    checkDependencies "perl" "lsuser" || {
        exit 1;
    }

    username_to_search=$1;

    # --------------------------------------------------------------
    #      Check if username is passed as a parameter, else ask
    # ---------------------------------------------------------------
    # 
    [[ -z "$1" ]] && {
        printf "Type username: ";

        read username_to_search;

        while [ -z "$(echo "$username_to_search" | tr -d '\n' | tr -d '\r' | tr -d ' ')" ]; do
            printf "Type username: ";

            read username_to_search;
        done
        #printf -- "--------------------------------\n";
        printf "\n";
    }


    # --------------------------------------------------------------
    #                   Check if username exists
    # ---------------------------------------------------------------
    #
    # Check for file: /etc/passwd
    if [ $(grep "^$username_to_search:" /etc/passwd | wc -l) -eq 0 ]; then
        printf "${red}ERROR${default} - User $username_to_search is not defined in the /etc/passwd file\n\n"
        
        return 1;
    fi

    # Check for file: /etc/security/passwd
    if [ $(grep -p "$username_to_search:" /etc/security/passwd 2>/dev/null | grep lastupdate | wc -l) -eq 0 ]; then
        printf "${red}ERROR${default} - User $username_to_search is not defined in the /etc/security/passwd file\n";
        printf "\tNote that this could be also because of a lack of permission\n\n";
        
        return 1;
    fi
    
    # Check for program: lsuser
    if [ $(lsuser -a maxage "$username_to_search" | wc -l) -eq 0 ]; then
        printf "${red}ERROR${default} - User $username_to_search is unknown to lsuser command\n"
        
        return 1;
    fi

  
  
    # --------------------------------------------------------------
    #                       Get actual data
    # ---------------------------------------------------------------
    #
    LastPwChgInSecs=$(lsuser -a lastupdate "$username_to_search" | cut -d= -f2)
    LastPwChgInDays=$(expr $LastPwChgInSecs \/ 86400 )
    LastPwChg=$(DTCe2h $LastPwChgInSecs)
    

    
    ExpInWks=$(lsuser -a maxage "$username_to_search" | cut -d= -f2);
    ExpInDays=$(expr $ExpInWks \* 7);
    ExpInSecs=$(expr $ExpInDays \* 86400);



    # Minimum number of days between password change
    MinDaysChange=$(expr $(lsuser -a minage "$username_to_search" | cut -d= -f2) \* 7);

    # Maximum number of days between password change
    MaxDaysChange=$(expr $(lsuser -a maxage "$username_to_search" | cut -d= -f2) \* 7);



    # Number of days of warning before password expires
    AccExpires=$(lsuser -a expires "$username_to_search" | cut -d= -f2);
    if [ "$AccExpires" -eq 0 ]; then
        AccExpires="never";
    fi;



    # Number of weeks after maxage. After this period the user cannnot login or change password. Needs help of an Administrator
    InactPwInWeeks=$(lsuser -a maxexpired "$username_to_search" | cut -d= -f2);
    if [[ "$InactPwInWeeks" == -1 ]]; then 
        InactPw="never";
    elif [[ "$InactPwInWeeks" == 0 ]]; then 
        InactPwInWeeks=$ExpInWks; 

        InactPwInDays=$(expr $InactPwInWeeks \* 7);
        InactPwInSecs=$(expr $InactPwInDays \* 86400);
        InactDateInSecs=$(expr $LastPwChgInSecs \+ $InactPwInSecs);
        InactPw=$(DTCe2h $InactDateInSecs);
    else 
        InactPwInDays=$(expr $InactPwInWeeks \* 7);
        InactPwInSecs=$(expr $InactPwInDays \* 86400);
        InactDateInSecs=$(expr $ExpInSecs \+ $InactPwInSecs);
        InactPw=$(DTCe2h $InactDateInSecs);
    fi;
    
    ExpDateInSecs=$(expr $LastPwChgInSecs \+ $ExpInSecs)
    ScadPw=$(DTCe2h $ExpDateInSecs | sed "s/\(....\).\(..\).\(..\) \(.*\)\$/\3-\2-\1 \4/")
    


    WarnPassExp=$(lsuser -a pwdwarntime "$username_to_search" | cut -d= -f2);
    if [ "$WarnPassExp" -eq 0 ]; then
        WarnPassExp="never"
    fi;




    # --------------------------------------------------------------
    #               Not used here but still useful flags
    # --------------------------------------------------------------
    # 
    # Unsuccessful login Count
    UnLgCnt=$(lsuser -a unsuccessful_login_count "$username_to_search" | cut -d= -f2);
    # Is Account Locked?
    AccLckd=$(lsuser -a account_locked "$username_to_search" | cut -d= -f2);



    # --------------------------------------------------------------
    #                       Display data
    # --------------------------------------------------------------
    # 
    printf "${unique_session_id}%-56s: %s\n"	"Last password change" 									"$LastPwChg";
    printf "${unique_session_id}%-56s: %s\n" 	"Password expires" 										"$ScadPw";
    printf "${unique_session_id}%-56s: %s\n" 	"Password inactive"										"$InactPw";
    printf "${unique_session_id}%-56s: %s\n" 	"Account expires"										"$AccExpires";
    printf "${unique_session_id}%-56s: %s\n" 	"Minimum number of days between password change" 		"$MinDaysChange";
    printf "${unique_session_id}%-56s: %s\n" 	"Maximum number of days between password change" 		"$MaxDaysChange";
    printf "${unique_session_id}%-56s: %s\n" 	"Number of days of warning before password expires" 	"$WarnPassExp";

    return 0;
}


# Date converter function: 
#       Date/Time converter from Epoch to Human, prints in the format "{LITERAL_SHORT_MONTH} {DAY}, {FULL_YEAR}"
# 
function DTCe2h {
    UnixTime=$1;

    perl -e "
        my \$ut = $UnixTime;
        my @abbr = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
        my (\$year,\$month,\$day,\$hour,\$min,\$sec) = (localtime(\$ut))[5,4,3,2,1,0];
        
        printf(\"%s %02d, %04d\", \$abbr[\$month], \$day, \$year+1900);
    ";
}


# Dependencies check function: 
#       Checks if all programs passed as parameters exist. 
#       Prints to stdOut programs that weren't found
# 
#       Usage: 
#           checkDependencies program1 program2 program3
# 
function checkDependencies {
    progs="$@";

    not_found_counter=0; 
    total_programs=$(echo "$progs" | wc -w); 

    for p in ${progs}; do
        command -v "$p" >/dev/null 2>&1 || {
            printf "${yellow}WARNING${default} - Program required is not installed: $p\n";

            not_found_counter=$(expr $not_found_counter + 1);
        }
    done

    [[ $not_found_counter -ne 0 ]] && {
        printf "\n"
        printf "${red}ERROR${default} - %d of %d programs were missing. Execution aborted\n" "$not_found_counter" "$total_programs";

        return 1;
    }

    return 0;
}


# Calling the main function 
main "$@";
