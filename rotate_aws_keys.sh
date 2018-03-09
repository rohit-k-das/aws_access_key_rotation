#!/bin/bash
# Global Variables
credentials_file=~/.aws/credentials

function print_intro(){
	echo
	echo -e "This script will only change the access key if it's present in ~/.aws/credentials\n"
	echo "Format in the credentials file:"
	echo "[profile_name]"
	echo "region ="
	echo "aws_access_key_id ="
	echo -e "aws_secret_access_key = \n"
	echo -e "\t\tOR\n"
	echo "[profile_name]"
	echo "aws_access_key_id ="
	echo "aws_secret_access_key ="
  	echo
}

function check_creds_file() {
	# let's check to make sure cred file exists in the first place
	if [ ! -f $credentials_file ];
	then
		echo "FATAL: AWS creds file not found at $credentials_file"
		exit 1
	else
		echo "Found credentials file at $credentials_file"
	fi

	# backup of credentials file
	cp $credentials_file aws_credentials_backup
	echo
	echo "Backup of credentials file aws_credentials_backup created."
  	echo

	return 0
}

function validate_ACCESS_KEY_format() {
	# Is input zero length
	inputvar=$1
	if [ -z "$inputvar" ]
	then
    	echo "Fatal: Access Key entered is empty"
		exit 1
  	fi
	# Is input 20 characters
	if [ ! ${#inputvar} -eq 20 ]
	then
	    echo "Fatal: Access Key entered is less than the required 20 Characters"
		exit 1
	fi
	#TODO Add validation to input (input must be alphanumeric, must be uppercase characters)
	return 0
}


function generate_new_key_and_replace() {
	Region=$1
	AWS_Account=$2
	number_of_lines_to_edit=$3
	key=$4

	echo "Checking the number of keys for user for $AWS_Account"
	num_of_keys=$(aws iam list-access-keys --profile=$AWS_Account 2> /dev/null| grep "AccessKeyId"| wc -l| sed -e 's/ //g')

	#Delete other AWS key if 2 keys are found.
	if [[ $num_of_keys -eq 2 ]];
	then

		other_access_key=$(aws iam list-access-keys --profile=$AWS_Account| grep "AccessKeyId"| cut -d ":" -f 2| sed -e 's/ //'| sed -e 's/\"//g'| cut -d "," -f 1| grep -v $key)
		echo "Found $num_of_keys access keys and $key $other_access_key."
		echo
		echo -n "Do you want to delete the access key $other_access_key that is not in $credentials_file (Y/y/N/n):"
		read choice
		if [[ $choice == "y"|| $choice == "Y" ]];
		then
			if $(aws iam delete-access-key --access-key-id $other_access_key --profile=$AWS_Account 2> /dev/null| sleep 3);
			then
				echo "Deleted access key $other_access_key."
				echo
			else
				echo "Unable to delete $other_access_key key. Contact administrator to delete $other_access_key."
				exit 1
			fi
		else
			exit 0
		fi
	elif [[ $num_of_keys -eq 1 ]];
	then
		echo "Found only $num_of_keys access key. Proceeding with rotating key $key."
		echo
	else
		echo "Didn't find keys. Aborting. Misconfiguration in $credentials_file"
		exit 1
	fi

	#Create new keys
	if $(aws iam create-access-key --profile=$AWS_Account > aws_temp_file 2> /dev/null| sleep 5)
	then
		echo "New keys created"
		echo
		#Gets Access Key ID and secret key from temp file and removes spaces, quotes
		new_access_key_id=$(grep AccessKeyId aws_temp_file| cut -d ":" -f 2| sed -e 's/ //'| sed -e 's/\"//g'| cut -d "," -f 1)
		Secret_key=$(grep SecretAccessKey aws_temp_file| cut -d ":" -f 2| sed -e's/ //g'| sed -e 's/\"//g'| cut -d "," -f 1)

		#Delete old key
		if $(aws iam delete-access-key --access-key-id $key --profile=$AWS_Account 2> /dev/null| sleep 3);
		then
			echo "Old key deleted successfully"
		else
			echo "Unable to delete old keys. Contact administrator to delete $key"
			exit 1
		fi
	else
		echo "Unable to create new keys"
		echo
		echo "Testing old keys"
		echo
		#Testing old keys still work
		if $(aws iam list-access-keys --profile=$AWS_Account &> /dev/null| sleep 3);
		then
			echo "Old keys still work."
			rm aws_temp_file
			exit 0
		fi
		exit 1
	fi

	#Get line number of profile and delete next 3/4 lines depending on variable number_of_lines_to_edit
	start_line_number=$(grep -n $AWS_Account $credentials_file| cut -d ":" -f 1)
	end_line_number=$((start_line_number + $number_of_lines_to_edit - 1))
	sed -i -e ''$start_line_number','$end_line_number'd' $credentials_file

	#Push change in credentials file
	echo >> $credentials_file
	echo "[$AWS_Account]" >> $credentials_file
	if [[ $Region != "Not_to_be_included" ]];
	then
		echo "region = $Region" >> $credentials_file
	fi
	echo "aws_access_key_id = $new_access_key_id" >> $credentials_file
	echo "aws_secret_access_key = $Secret_key" >> $credentials_file
	echo
	echo "Done rotating key $key"
	echo
	return 0
}

function get_profile_name(){
	key=$1
	#Check for "[" in profile name in credentials file so as to find the profile name
	if grep -B 2 $key $credentials_file| grep -q "\[";
	then
		#Get profile name from access key id which disregards brackets with regular expression
		AWS_Account=$(grep -B 2 $key $credentials_file| head -1| sed -e 's/\[//g'| sed -e 's/\]//g')

		#Get Region from access key id which disregards space
		Region=$(grep -B 1 $key $credentials_file| head -1| cut -d "=" -f 2| sed -e 's/ //g')
		if [[ -z $Region ]];
		then
			Region="Not_to_be_included"
		fi
		number_of_lines_to_edit=4
	else
		#Get profile name from access key id which disregards brackets with regular expression
		AWS_Account=$(grep -B 1 $key $credentials_file| head -1| sed -e 's/\[//g'| sed -e 's/\]//g')
		Region="Not_to_be_included"
		number_of_lines_to_edit=3
	fi

	echo
	echo "Access key found for profile $AWS_Account"
	echo
	#Test current keys for profile
	echo "Testing current keys for $AWS_Account"
	echo
	if $(aws iam list-access-keys --profile=$AWS_Account &> /dev/null);
	then
		echo "Current keys work."
		echo
	else
		echo "Current key $key doesn't work either due to wrong key or aws command not found. Contact administrator"
		exit 1
	fi
	return 0
}

function test_new_creds(){
	new_access_key_id=$1
	Secret_key=$2
	AWS_Account=$3

	#Test new keys
	echo "Checking presence of new keys and secret id in credential file"
	if grep -q "$new_access_key_id" $credentials_file;
	then
		if grep -q "$Secret_key" $credentials_file;
		then
			echo "New keys found in $credentials_file"
			echo
			echo "Checking if the new keys work"

			#Checking if new key works
			if $(aws iam list-access-keys --profile=$AWS_Account &> /dev/null| sleep 1);
			then
				echo "New key works."
				echo

				#Delete temp file and backup
				echo "Removing temp and backup file"
				rm -f aws_temp_file
				rm aws_credentials_backup
			else
				echo "New keys don't work."

				#Check for the presence of aws_temp_file that has new keys
				if [[ ! -f aws_temp_file ]];
				then
					cp aws_credentials_backup $credentials_file
				else
					echo "Please hand edit from aws_temp_file."
				fi
			fi
		else
			echo "Problem updating credential file. Secret key not found. Please check aws_temp_file and update manually"
		fi
	else
		echo "Problem updating credential file. Access key ID not found. Please check aws_temp_file and update manually"
	fi
	return 0
}

function format_credentials_file(){

	while IFS= read -r line;
	do
  		array+=("$line")
  done < $credentials_file
	# read entire creds file into an array
	while IFS= read -r line;
	do
  		array+=("$line")
  done < $credentials_file

  # TODO Parse file by checking array of srings
  # 1st line must contain a []
	# 2nd line may contain region =
	# 3rd line must contain aws_access_key_id =
	# 4th line must contain aws_secret_access_key =
  # skip any line that is blank
	# startover for next profile or end parse as failed.

	#echo $array
}

### MAIN PROGRAM #######
print_intro
echo -n "Do you want to proceed(Y/y/N/n):"
read choice
if [[ $choice == "y"|| $choice == "Y" ]];
then
echo
#Checks presence of cred file and creates backup
check_creds_file

echo "Format for entering keys: Key1, Key2, Key3"
echo -n "Enter Access Key ID(s): "
read ACCESS_KEY
keys=$(echo $ACCESS_KEY | tr "," "\n")

	for key in $keys;
	do
		validate_ACCESS_KEY_format $key

		#Check if access key found
		if grep -q $key $credentials_file;
		then
			#Get profile name, Region if possible and number of lines to edit in the credentials file
			get_profile_name $key

			#Create new key and delete old one
			generate_new_key_and_replace $Region $AWS_Account $number_of_lines_to_edit $key

			#Check if new key is not blank
			if [[ -z $new_access_key_id ]];
			then
				echo "New key created is blank. Check aws_temp_file"
				exit 1
			fi

			if [[ -z $Secret_key ]];
			then
				echo "New Secret key created is blank. Check aws_temp_file"
				exit 1
			fi

			#Test new credentials were created
			test_new_creds $new_access_key_id $Secret_key $AWS_Account

			#Format credentials file
			format_credentials_file

		else
			echo "Access Key $key not found in" $credentials_file
			echo "Removing aws_credentials_backup file"
			rm aws_credentials_backup
		fi
	done
else
	exit 0
fi

