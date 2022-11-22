#!/bin/bash
# TODO:
# all incoming files from tt have to kebab case and lower case
# integrate tags properly from tt and vimwiki
# tags with vimwiki proper format first line
# launch seperate windows for multiple task preview. right now main tt window gets blocked after launching one note

set -e

notes_root_folder="$HOME/vimwiki"
diary_root_folder="$HOME/vimwiki/diary"

# uuid is first passed in
received_uuid=$@
echo $received_uuid

uda_diary_entry="diary_entry"
uda_diary_entry_value_yes="Y"
uda_diary_entry_value_no="N"

uda_tags_updated="tags_updated"
uda_tags_updated_value_yes="Y"
uda_tags_updated_value_no="N"


regex_d1="([a-z]+)"
regex_number_check="^[0-9]+$"
regex_number_check_2="^d#([0-9]+$)"
regex_for_http_beginning="^(https)"

echo_empty_line(){
  echo "" >>  $1
}



# args are task uuid, uda value to be update and new value for update
update_taskwarrior_uuid_uda(){
  # task $received_uuid modify $uda_1:$uda_1_value_1
  task $1 modify $2:$3
}
get_taskwarrior_uuid_attribute(){
  # $(task _get $received_uuid.project)
  task _get $1'.'$2
}
# relative to root
generate_foldername(){
  echo "$notes_root_folder/$(echo $1| sed 's,\.,/,g')"
}
# relative to vimwiki
generate_relative_foldername(){
  echo "/$(echo $1 | sed 's,\.,/,g')"
}
new_folder_creation(){
  mkdir -p $1
}
get_task_filename_for_vimwiki(){
  # echo "$foldername/${received_uuid}.wiki"
  echo "$(generate_foldername "$(get_taskwarrior_uuid_attribute $1 "project")")/$1.wiki"
}
get_present_date_diary_file(){
  mkdir -p $diary_root_folder
  echo "$diary_root_folder/$(date +"%Y-%m-%d").wiki"
}
generate_note_entry_for_present_dairy(){
  echo "[[$(generate_relative_foldername $(get_taskwarrior_uuid_attribute $1 "project"))/$1|$(get_taskwarrior_uuid_attribute  $1 "description")]]"
}
# format task description later used for linking and references etc.
format_task_description(){
  # get_taskwarrior_uuid_attribute $received_uuid "description"
  new_task_description=""
  if [[ $(get_taskwarrior_uuid_attribute $1 "description") =~ $regex_for_http_beginning ]];then
    # echo "found http"
    read -p "Enter the content header(use quotes): " content_header
    read -p "Continue? (Y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
    new_task_description=$content_header
    # echo $new_task_description
  fi
  # replace quotes with empty, replace space with hypen, make all lower case
  new_task_description=$(echo $(get_taskwarrior_uuid_attribute $1 "description")| sed 's,",,g' | sed 's,\ ,-,g' | tr [:upper:] [:lower:]) 
  #load old description into tmp_value_holder
  update_taskwarrior_uuid_uda $1 "tmp_value_holder" $(get_taskwarrior_uuid_attribute $1 "description")
  #load new task description
  # echo "YY"
  update_taskwarrior_uuid_uda $1 "description" $new_task_description
  echo $new_task_description
}
# single arrow for overwrite
# double for append
generate_note_template(){

  tmp_filename="$(get_task_filename_for_vimwiki $1)"
  echo $tmp_filename

  # empty aline to accomodate for tags
  echo_empty_line $tmp_filename
  echo_empty_line $tmp_filename
  echo "= $(get_taskwarrior_uuid_attribute $1 "description") =" >> $tmp_filename

  echo_empty_line $tmp_filename
  echo "Entry : "$(date +"%Y-%m-%d") >> $tmp_filename

  echo_empty_line $tmp_filename
  echo "=== References ===" >>  $tmp_filename
  # will http url inserted
  if [[ -z "$(get_taskwarrior_uuid_attribute $1 "tmp_value_holder")" ]]
  then
    echo "put http into references"
    echo "- "$(get_taskwarrior_uuid_attribute $1 "tmp_value_holder") >>  $tmp_filename
  else
    echo "- " >>  $tmp_filename
  fi

  echo_empty_line $tmp_filename
  echo "=== Notes ===" >>  $tmp_filename
}
# consolidate tags from tt and vim wiki
# will be done twice once before entering vimwiki and once when leaving vimwiki
process_tags(){
  # fetch first line of file
  declare -A tmp_assoc_tag_array
  regex_tag_grep='^:(\S*):$'
  local tmp_filename=$(get_task_filename_for_vimwiki $1)
  local tags_from_vimwiki_file=$(head -1 $tmp_filename)
  if [[ $tags_from_vimwiki_file =~ $regex_tag_grep ]]; then
    IFS=':' read -r -a tag_array_from_file <<< "${BASH_REMATCH[1]}" 
    for tag in "${tag_array_from_file[@]}"
    do
      tmp_assoc_tag_array[$tag]="true"
    done
  fi
  tags_from_tt=$(get_taskwarrior_uuid_attribute $1 "tags")
  if [[ ! -z $tags_from_tt ]]
  then
    IFS=',' read -r -a tag_array_from_file <<<  $tags_from_tt
    for tag in "${tag_array_from_file[@]}"
    do
      #if decimal number prefix d# incoming ftom tw
      if [[ $tag =~ $regex_number_check_2 ]]
      then
        # d# : decimal number prefix
        # echo "incoming from tt"
        tag=${BASH_REMATCH[1]}
      fi
      tmp_assoc_tag_array[$tag]="true"
    done
  fi
  # add default tags ... project name
  local default_tags=$(get_taskwarrior_uuid_attribute $1 "project")
  local default_tags_array
  IFS='.' read -r -a default_tags_array <<<  $default_tags
  for tag in "${default_tags_array[@]}"
  do
    tag=$(echo $tag | sed 's,-,_,g')
    tmp_assoc_tag_array[$tag]="true"
  done
  # echo "Default"
  # echo "${default_tags_array[@]}"

  local string_for_vimwiki=":"
  local commmand_arg_for_tt

  for key in "${!tmp_assoc_tag_array[@]}"
  do 
    # kebab case is problenm for tt
    key=$(echo $key | sed 's,-,_,g' | tr [:upper:] [:lower:])
    # prepare string for vimwiki
    string_for_vimwiki+=$key
    string_for_vimwiki+=:

    # decimal numbers as tags issue in tw
    if [[ "$key" =~ $regex_number_check ]]
    then
      # d# : decimal number prefix
      key=d#$key
    fi

    commmand_arg_for_tt+=+$key
    commmand_arg_for_tt+=' '
  done
  # skip trailing space for tt
  commmand_arg_for_tt=$(echo $commmand_arg_for_tt | sed 's,\ *$,,g')
  echo $commmand_arg_for_tt
  task $1 modify $commmand_arg_for_tt

  # echo $commmand_arg_for_tt
  echo $string_for_vimwiki
  # update vimwiki tags
  sed -i "1s/.*/$string_for_vimwiki/" $tmp_filename
  # prepare command input for tt
  # associtive array length test
}
new_task_added_flow(){
  # check if folder exists
  foldername_tocheck=$(generate_foldername "$(get_taskwarrior_uuid_attribute $1 "project")")
  echo $foldername_tocheck
  if [ ! -d "$foldername_tocheck" ]; then
    new_folder_creation $foldername_tocheck
  fi

  # check if diary for day exists
  if [ ! -f $(get_present_date_diary_file) ]; then
    # echo "creating diary file"
    touch $(get_present_date_diary_file)
  fi

  # update tt description 
  format_task_description $1

  # insert proper link into date diary
  echo $(generate_note_entry_for_present_dairy $1) >> $(get_present_date_diary_file)

  #create note file .. will work since necessary fodler created
  touch $(get_task_filename_for_vimwiki $1) 

  #load template
  generate_note_template $1

  # update tt diary_entry 
  update_taskwarrior_uuid_uda $1 $uda_diary_entry $uda_diary_entry_value_yes

  #consolidate tags
  # first time
  process_tags $1

}

sanity_check_before_vimwiki(){
  # project assigned
  if [[ -z $(get_taskwarrior_uuid_attribute $1 "project") ]]
  then
    read -p "Project should have assigned. Some Error"
    exit 1
  fi
  # folder exists
  if [ ! -d "$(generate_foldername "$(get_taskwarrior_uuid_attribute $1 "project")")" ]
  then
    read -p "Folder should have existed. Some Error"
    exit 1
  fi
  # file exists
  if [ ! -f $(get_task_filename_for_vimwiki $1) ]
  then
    read -p "File should have existed. Some Error"
    exit 1
  fi
}
# MAIN FUNCTION TO CALL
process_task_from_tt(){
  # check for entry in vimwiki
  if [[ $(get_taskwarrior_uuid_attribute $1 "diary_entry") == $uda_diary_entry_value_yes ]]
  then
    # entry exists .. open
    echo "Exits"
    sanity_check_before_vimwiki $1
    #consolidate tags.. first time
    process_tags $1
  else
    echo "New"
    # entry does not exist
    # new task flow
    # to not be called if project not assigned
    # wont allow for project input here since tt has a nice interface for it and dropdown
    if [[ -z $(get_taskwarrior_uuid_attribute $1 "project") ]]
    then
      read -p "Project should be assigned. Acknowledge?" 
      exit 1
    fi
    new_task_added_flow $1
  fi
  # launch st
  st -e vim $(get_task_filename_for_vimwiki $1) &> /dev/null 2>&1 &
  # st -e nvim +VimwikiRebuildTags $(get_task_filename_for_vimwiki $1) &> /dev/null 2>&1 &

  #consolidate tags.. second time
  # process_tags $1
}

process_task_from_tt $received_uuid
test_progress(){
  process_tags $received_uuid
  # new_task_added_flow $received_uuid
  # generate_note_template $received_uuid
  # generate_note_entry_for_present_dairy $received_uuid 
  # generate_relative_foldername $(get_taskwarrior_uuid_attribute $received_uuid "project") 
  # format_task_description $received_uuid
  # get_present_date_diary_file
  # get_task_filename_for_vimwiki $received_uuid
  # get_taskwarrior_uuid_attribute $received_uuid "project"
  # get_taskwarrior_uuid_attribute $received_uuid "diary_entry"
  # get_taskwarrior_uuid_attribute $received_uuid "description"
}
# test_progress
