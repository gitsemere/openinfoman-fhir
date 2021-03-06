(:~
: This is the Care Services Discovery stored query registry
: @version 1.1
: @see https://github.com/openhie/openinfoman
:
:)
module namespace fadpt = "https://github.com/openhie/openinfoman/adapter/fhir";



(:Import other namespaces.  Set default namespace  to os :)
import module namespace csd_webconf =  "https://github.com/openhie/openinfoman/csd_webconf";
import module namespace csd_webui =  "https://github.com/openhie/openinfoman/csd_webui";
import module namespace csr_proc = "https://github.com/openhie/openinfoman/csr_proc";
import module namespace csd_dm = "https://github.com/openhie/openinfoman/csd_dm";

declare namespace csd = "urn:ihe:iti:csd:2013";
declare namespace atom = "http://www.w3.org/2005/Atom";
declare namespace fhir = "http://hl7.org/fhir";
declare namespace hapi = "java:org.intrahealth.hapi_transformer";

declare function fadpt:is_fhir_function($search_name) {
  let $function := csr_proc:get_function_definition($search_name)
  let $ext := $function//csd:extension[  @urn='urn:openhie.org:openinfoman:adapter' and @type='fhir']
  return (count($ext) > 0) 
};


declare function fadpt:has_feed($search_name,$doc_name) {
  (fadpt:is_fhir_function($search_name) and csd_dm:document_source_exists($doc_name))
};

declare function fadpt:get_base_url($search_name) {
  fadpt:get_base_url($search_name,csd_webui:generateURL())
};
declare function fadpt:get_base_url($search_name,$base_url) {
  concat($base_url,'CSD/adapter/fhir/' ,$search_name)
};



declare function fadpt:format_entities($doc,$entities,$entityType,$format) {
  switch ($entityType)
  case "Practitioner" 
    return 
      if ($format = ('application/json+fhir' ,  'application/json' ,'json'))
      then for $entity in $entities return fadpt:represent_provider_as_practitioner_JSON($doc,$entity)
      else for $entity in $entities return fadpt:represent_provider_as_practitioner($doc,$entity)
  case "Location"
    return
      if ($format = ('application/json+fhir' ,  'application/json' ,'json'))
      then for $entity in $entities return  fadpt:represent_facility_as_location_JSON($doc,$entity) 
      else for $entity in $entities return  fadpt:represent_facility_as_location($doc,$entity)
  case "Organization"
    return
	if ($format = ('application/json+fhir' ,  'application/json' ,'json'))
	then for $entity in $entities return  fadpt:represent_organization_as_organization_JSON($doc,$entity)
	else for $entity in $entities return  fadpt:represent_organization_as_organization($doc,$entity)
  default return ()
};




declare function fadpt:create_feed_from_entities($entities,$requestParams) {
  let $search_name := string($requestParams/@urn)
  let $doc_name := string($requestParams/@resource)
  let $base_url := string($requestParams/@base_url)
  let $function := csr_proc:get_function_definition($search_name)
  let $entity := string(($function/csd:extension[ @urn='urn:openhie.org:openinfoman:adapter:fhir:read']/@type)[1])
  let $link := concat(fadpt:get_base_url($search_name,$base_url),'/' , $doc_name ,'/',$entity )
  let $title := concat("CSD entity as FHIR ",$entity)
  return 
  <atom:feed>
    <atom:title>{$title}</atom:title>
    <atom:link href="{$link}" rel="self"/>
    <atom:updated>{current-dateTime()}</atom:updated>
     {
       for $entity in $entities
       let $ent_link := concat($link,"/", ($entity//fhir:identifier)[1])
       return 
         <atom:entry>
	   <atom:link href="{$ent_link}"/>
	   <atom:content type="text/xml">{$entity}</atom:content>
	 </atom:entry>
     }
  </atom:feed>

};

declare function fadpt:create_feed_from_entities_JSON($entities,$requestParams) {
  let $search_name := string($requestParams/@function)
  let $doc_name := string($requestParams/@resource)
  let $base_url := string($requestParams/@base_url)
  let $function := csr_proc:get_function_definition($search_name)
  let $entity := string(($function/csd:extension[ @urn='urn:openhie.org:openinfoman:adapter:fhir:read']/@type)[1])
  let $link := concat(fadpt:get_base_url($search_name,$base_url),'/' , $doc_name ,'/',$entity )
  let $title := concat("CSD entity as FHIR (JSON) ",$entity)
  return 
  <atom:feed>
    <atom:title>{$title}</atom:title>
    <atom:link href="{$link}" rel="self"/>
    <atom:updated>{current-dateTime()}</atom:updated>
     {
       for $entity in $entities
       return 
         <atom:entry>
	   <atom:content type="application/json">{$entity}</atom:content>
	 </atom:entry>
     }
  </atom:feed>

};



(:
   Function to turn a CSD Organization entity into a FHIR Organization
:)

declare function fadpt:represent_organization_as_organization($doc,$organization)
{
  (: See http://www.hl7.org/implement/standards/fhir/organization.html :)
  <fhir:Organization >
    <fhir:id>{string($organization/@entityID)}</fhir:id>
    <fhir:identifier>{string($organization/@entityID)}</fhir:identifier>
    <fhir:name>{($organization/csd:primaryName)[1]/text()}</fhir:name>    
    {
      (
       (: Note: nothing readily apparent for description :)
       (:Note:  FHIR allows only one facility type:)
       for $type in  ($organization/csd:codedType)[1] 
       return  <fhir:type><fhir:coding><fhir:system>urn:oid:{string($type/@codingScheme)}</fhir:system><fhir:code>{string($type/@code)}</fhir:code></fhir:coding></fhir:type>
       ,
       for $contact in  $organization/csd:contactPoint/csd:codedType
       return  
        <fhir:telecom>
	  <fhir:system value="urn:oid:{string($contact/@code)}"/>
	  <fhir:value value="{$contact/text()}"/>
	</fhir:telecom>
       ,
       (: Note: address is a bit weird.. which address? FHIR only allows for one. In CSD a provider 
          can have a practice address as well as be assocaited to multiple facilities, each with their own address:)
       let $address :=  ($organization/csd:address[@type='Practice'])[1]
       return 
	 if (exists($address))	   
	 then	   
	   <fhir:address>
	     {(
	       for $al in $address/csd:addressLine[@component = 'streetAddress']
	       return <fhir:line>{$al/text()}</fhir:line>
	       ,
	       for $city in ($address/csd:addressLine[@component = 'city'])[1]
	       return <fhir:city>{$city/text()}</fhir:city>
	       ,
	       for $state in ($address/csd:addressLine[@component = 'stateProvince'])[1]
	       return <fhir:state>{$state/text()}</fhir:state>
	       ,
	       for $zip in ($address/csd:addressLine[@component = 'postalCode'])[1]
	       return <fhir:zip>{$zip/text()}</fhir:zip>
	       ,
	       for $country in ($address/csd:addressLine[@component = 'country'])[1]
	       return <fhir:country>{$country /text()}</fhir:country>
	     )}	     
           </fhir:address>
	 else ()
	,
	(:  Note: FHIR only permits one managinh organization but CSD has many :)
	for $org in ($organization/csd:parent)[1]
	   (: Note: base for URL for reference should maybe be handled by stored function extension metadata   :)
	   return <fhir:partOf><fhir:reference>{string($org/@entityID)}</fhir:reference></fhir:partOf>
	,
	(:May need to map codes :)
        <fhir:status>{string($organization/csd:record/@status)}</fhir:status>
	(:Note nothing immediately obvious for FHIR partOf or for FHIR mode :)
     )
    }
      
  </fhir:Organization>
};




(:
   Function to turn a CSD Facility entity into a FHIR Location
:)

declare function fadpt:represent_facility_as_location($doc,$facility)
{
  (: See http://www.hl7.org/implement/standards/fhir/location.html :)
  <fhir:Location >
    <fhir:id>{string($facility/@entityID)}</fhir:id>
    <fhir:identifier>{string($facility/@entityID)}</fhir:identifier>
    <fhir:name>{($facility/csd:primaryName)[1]/text()}</fhir:name>    
    {
      (
       (: Note: nothing readily apparent for description :)
       (:Note:  FHIR allows only one facility type:)
       for $type in  ($facility/csd:codedType)[1] 
       return  <fhir:type><fhir:coding><fhir:system>urn:oid:{string($type/@codingScheme)}</fhir:system><fhir:code>{string($type/@code)}</fhir:code></fhir:coding></fhir:type>
       ,
       for $contact in  $facility/csd:contactPoint/csd:codedType
       return  
        <fhir:telecom>
	  <fhir:system value="urn:oid:{string($contact/@code)}"/>
	  <fhir:value value="{$contact/text()}"/>
	</fhir:telecom>
       ,
       (: Note: address is a bit weird.. which address? FHIR only allows for one. In CSD a provider 
          can have a practice address as well as be assocaited to multiple facilities, each with their own address:)
       let $address :=  ($facility/csd:address[@type='Practice'])[1]
       return 
	 if (exists($address))	   
	 then	   
	   <fhir:address>
	     {(
	       for $al in $address/csd:addressLine[@component = 'streetAddress']
	       return <fhir:line>{$al/text()}</fhir:line>
	       ,
	       for $city in ($address/csd:addressLine[@component = 'city'])[1]
	       return <fhir:city>{$city/text()}</fhir:city>
	       ,
	       for $state in ($address/csd:addressLine[@component = 'stateProvince'])[1]
	       return <fhir:state>{$state/text()}</fhir:state>
	       ,
	       for $zip in ($address/csd:addressLine[@component = 'postalCode'])[1]
	       return <fhir:zip>{$zip/text()}</fhir:zip>
	       ,
	       for $country in ($address/csd:addressLine[@component = 'country'])[1]
	       return <fhir:country>{$country /text()}</fhir:country>
	     )}	     
           </fhir:address>
	 else ()
	,
        (: Note: nothing immediate for Physical type :)
	if (exists($facility/csd:geocode)) then
	  <fhir:position>
	    <fhir:longitude>{$facility/csd:geocode/csd:longitude}</fhir:longitude>
	    <fhir:latitude>{$facility/csd:geocode/csd:latitude}</fhir:latitude>
	    <fhir:altitude>{$facility/csd:geocode/csd:altitude}</fhir:altitude>
	  </fhir:position>
	else ()
	,
	(:  Note: FHIR only permits one managinh organization but CSD has many :)
	for $org in ($facility/csd:organizations/csd:organization)[1]
	   (: Note: base for URL for reference should maybe be handled by stored function extension metadata   :)
	   return <fhir:managingOrganization><fhir:reference>{string($org/@entityID)}</fhir:reference></fhir:managingOrganization>
	,
	(:May need to map codes :)
        <fhir:status>{string($facility/csd:record/@status)}</fhir:status>
	(:Note nothing immediately obvious for FHIR partOf or for FHIR mode :)
     )
    }
      
  </fhir:Location>
};



(:
   Function to turn a CSD Provider entity into a FHIR Practitioner
:)

declare function fadpt:represent_provider_as_practitioner($doc,$provider) 
{
  (: See http://www.hl7.org/implement/standards/fhir/practitioner.html :)
  <fhir:Practitioner >
    <fhir:id>{string($provider/@entityID)}</fhir:id>
    <fhir:identifier><fhir:value>{string($provider/@entityID)}</fhir:value><fhir:system>{string($provider/csd:record/@sourceDirectory)}</fhir:system></fhir:identifier> 
    {
      for $otherID in $provider/csd:otherID
      let $auth := string($otherID/@assigningAuthorityName)
      let $code := string($otherID/@code)
      let $val := $otherID/text()
      return <fhir:identifier><fhir:type>{$code}</fhir:type><fhir:value>{$val}</fhir:value><fhir:system>{$auth}</fhir:system></fhir:identifier> 
    }
    {
        for $name in ($provider/csd:demographic/csd:name)[1] (:why does FHIR only allow one fhir:text and name element :)
	let $cn := ($name/csd:commonName)[1]/text()  
	let $sn := ($name/csd:surname)[1]/text()
	let $gn := ($name/csd:forename)[1]/text()
	let $hon := ($name/csd:honorific)[1]/text()
	return
	  <fhir:name>
	    <fhir:text value="{$cn}"/>
	    <fhir:family value="{$sn}"/>
	    <fhir:given value="{$gn}"/>
	    <fhir:prefix value="{$hon}"/>	  
	  </fhir:name>
    }
    {
      (
       for $contact in  $provider/csd:demographic/csd:contactPoint/csd:codedType
       return  
        <fhir:telecom>
	  <fhir:system value="urn:oid:{string($contact/@code)}"/>
	  <fhir:value value="{$contact/text()}"/>
	</fhir:telecom>
       ,
       (: Note: address is a bit weird.. which address? FHIR only allows for one. In CSD a provider 
          can have a practice address as well as be assocaited to multiple facilities, each with their own address:)
       let $address :=  ($provider/csd:demographic/csd:address[@type='Practice'])[1]
       return 
	 if (exists($address))
	 then
	   <fhir:address>
	     {(
	       for $al in $address/csd:addressLine[@component = 'streetAddress']
	       return <fhir:line>{$al/text()}</fhir:line>
	       ,
	       for $city in ($address/csd:addressLine[@component = 'city'])[1]
	       return <fhir:city>{$city/text()}</fhir:city>
	       ,
	       for $state in ($address/csd:addressLine[@component = 'stateProvince'])[1]
	       return <fhir:state>{$state/text()}</fhir:state>
	       ,
	       for $zip in ($address/csd:addressLine[@component = 'postalCode'])[1]
	       return <fhir:zip>{$zip/text()}</fhir:zip>
	       ,
	       for $country in ($address/csd:addressLine[@component = 'country'])[1]
	       return <fhir:country>{$country /text()}</fhir:country>
	     )}
           </fhir:address>
	 else ()
	,
	(: Note: what code set should we use in our output? :) 
	let $gender := ($provider/csd:demographic/csd:gender)[1]
	return 
	  if (exists($gender))  then  
	    <fhir:gender>{$gender/text()}
	      <fhir:coding>
		<fhir:system>urn:oid:2.25.309768652999692686176651983274504471835.999.403</fhir:system>
		<fhir:code>{$gender/text()}</fhir:code>
	      </fhir:coding>
	    </fhir:gender>
	  else ()
	,
	let $dob := ($provider/csd:demographic/csd:dateOfBirth)[1]
	return 
	  if (exists($dob))  then  <fhir:birthDate>{$dob/text()}</fhir:birthDate>
	  else ()
	,
	(:  Note: note supported under standard CSD   <photo><!-- 0..* Attachment Image of the person --></photo>  :)
	for $org in ($provider/csd:organizations/csd:organization)
	  (: Note: base for URL for reference should maybe be handled by stored function extension metadata   :)
	  (:              see http://www.hl7.org/implement/standards/fhir/base-definitions.html#ResourceReference.reference :)
	return <fhir:organization><fhir:reference>{string($org/@entityID)}</fhir:reference></fhir:organization>
	,
	(: Note: perhaps this should be for services -- see remark below on <fhir:period/> :)
	for $role in ($provider/csd:codedType)
	return <fhir:role><fhir:coding><fhir:system>urn:oid:{string($role/@codingScheme)}</fhir:system><fhir:code>{string($role/@code)}</fhir:code></fhir:coding></fhir:role>
	,
	for $specialty in ($provider/csd:specialty)
	return <fhir:specialty><fhir:coding><fhir:system>{string($specialty/@codingScheme)}</fhir:system><fhir:code>{string($specialty/@code)}</fhir:code></fhir:coding></fhir:specialty>
	,
	(: Note: note supported <period><!-- 0..1 Period      The period during which the practitioner is authorized to perform in these role(s) § --></period> 
           unless we interpret the <fhir:role/> element as a service
	:)
	for $fac in ($provider/csd:facilities/csd:facility)
	   (: Note: base for URL for reference should maybe be handled by stored function extension metadata   :)
	  (:              see http://www.hl7.org/implement/standards/fhir/base-definitions.html#ResourceReference.reference :)
	return <fhir:location><fhir:reference>{string($fac/@entityID)}</fhir:reference></fhir:location>
	,  
	for $qual in ($provider/csd:credential)
	return 
	  <fhir:qualification>
	    <fhir:code><fhir:coding><fhir:system>urn:oid:{string($qual/@codingScheme)}</fhir:system><fhir:code>{string($qual/@code)}</fhir:code></fhir:coding></fhir:code>
	    <fhir:period>
	       {if (exists($qual/csd:credenitalIssueDate)) then   <fhir:start>{$qual/csd:credenitalIssueDate}</fhir:start> else ()}
	       {if (exists($qual/csd:credentialRenewalDate)) then  <fhir:end>{$qual/csd:credentialRenewalDate}</fhir:end> else ()}
	    </fhir:period>
	    {
	      (:Note: I don't think this is quite correct.  It wants it to be an organization ID :)
	      if (exists($qual/csd:issuingAuthority)) then <fhir:issuer><fhir:reference>{$qual/csd:issuingAuthority/text()}</fhir:reference></fhir:issuer> else () 
	    }
	  </fhir:qualification>
       ,
       for $lang in $provider/csd:language
       return  <fhir:communication><fhir:coding><fhir:system>urn:oid:{string($lang/@codingScheme)}</fhir:system><fhir:code>{string($lang/@code)}</fhir:code></fhir:coding></fhir:communication>
     )
    }
	 
      
  </fhir:Practitioner>
};



(:
   Function to turn a CSD Facility  entity into a FHIR Location as JSON
:)

declare function fadpt:represent_facility_as_location_JSON($doc,$facility) {
  fadpt:represent_facility_as_location_JSON($doc,$facility,false())
};

declare function fadpt:represent_facility_as_location_JSON($doc,$facility,$as_xml)
{
  let $xml:= 
    <json  type="object">
      <resourceType>Location</resourceType>
      <id>{string($facility/@entityID)}</id>
      <identifier type="array">
      <_ type="object">
	<id>{string($facility/@entityID)}</id>
	<value>{string($facility/@entityID)}</value>
	<system>{string($facility/csd:record/@sourceDirectory)}</system>
	</_>
	{
	  for $otherID in $facility/csd:otherID
	  let $auth := string($otherID/@assigningAuthorityName)
	  let $code := string($otherID/@code)
	  let $val := $otherID/text()
	  return 
	    <_ type="object">
	      <type>{$code}</type>
	      <value>{$val}</value>
	      <system>{$auth}</system>
	    </_>
	}	
      </identifier>
      <name>{($facility/csd:primaryName)[1]/text()}</name>
      <type type="array">
	{
	  for $role in ($facility/csd:codedType)
	  return 
	    <_ type="object">
	      <coding type="array">
	        <_ type="object">
		  <system>urn:oid:{string($role/@codingScheme)}</system>
		  <code>{string($role/@code)}</code>
		</_>
	      </coding>
	    </_>
	}
      </type>
      <telecom type="array">
	{
	  for $contact in  $facility/csd:contactPoint/csd:codedType
	  return 
	    <_ type="object">
	      <system>urn:oid:{string($contact/@code)}</system>
	      <value>{$contact/text()}</value>
	    </_>
	}
      </telecom>
      {
	for $address in ($facility/csd:demographic/csd:address[@type='Practice'])[1]
	return 
	   <address type="object">
	     <use>{string($address/@type)}</use>
	     <line type="array">
	       {
		 for $al in $address/csd:addressLine[@component = 'streetAddress']
		 return <_>{$al/text()}</_>
	       }
	     </line>
	     { 
	       for $city in ($address/csd:addressLine[@component = 'city'])[1]
	       return <city>{$city/text()}</city>
	     }
	     {
	       for $state in ($address/csd:addressLine[@component = 'stateProvince'])[1]
	       return <state>{$state/text()}</state>
	     }
	     {
	       for $zip in ($address/csd:addressLine[@component = 'postalCode'])[1]
	       return <zip>{$zip/text()}</zip>
	     }
	     {
	       for $country in ($address/csd:addressLine[@component = 'country'])[1]
	       return <country>{$country /text()}</country>
	     }
           </address>
      }
      {
	for $org in ($facility/csd:organizations/csd:organization)[1]
	   (: Note: base for URL for reference should maybe be handled by stored function extension metadata   :)
	   return <managingOrganization type="object"><reference>{string($org/@entityID)}</reference></managingOrganization>
      }
      {
	switch ($facility/csd:record/@status)
	case "106-001" return <status>active</status>
	case "106-002" return <status>Inactive</status>
	default return ()	  
      }
    </json>
    
  return 
    if ($as_xml) 
    then $xml
    else json:serialize($xml,map{"format":"direct"})  

};


(:
   Function to turn a CSD Organization entity into a FHIR Organization as JSON
:)

declare function fadpt:represent_organization_as_organization_JSON($doc,$organization) {
  fadpt:represent_organization_as_organization_JSON($doc,$organization,false())
};

declare function fadpt:represent_organization_as_organization_JSON($doc,$organization,$as_xml)
{
  let $xml:= 
    <json  type="object">
      <resourceType>Organization</resourceType>
      <id>{string($organization/@entityID)}</id>
      <identifier type="array">
      <_ type="object">
	<value>{string($organization/@entityID)}</value>
	<system>{string($organization/csd:record/@sourceDirectory)}</system>	  
	</_>
	{
	  for $otherID in $organization/csd:otherID
	  let $auth := string($otherID/@assigningAuthorityName)
	  let $code := string($otherID/@code)
	  let $val := $otherID/text()
	  return 
	    <_ type="object">
	      <type>{$code}</type>
	      <value>{$val}</value>
	      <system>{$auth}</system>
	    </_>
	}	
      </identifier>
      <name>{($organization/csd:primaryName)[1]/text()}</name>
      <type type="array">
	{
	  for $role in ($organization/csd:codedType)
	  return 
	    <_ type="object">
	      <coding type="array">
	        <_ type="object">
		  <system>urn:oid:{string($role/@codingScheme)}</system>
		  <code>{string($role/@code)}</code>
		</_>
	      </coding>
	    </_>
	}
      </type>
      <telecom type="array">
	{
	  for $contact in  $organization/csd:contactPoint/csd:codedType
	  return 
	    <_ type="object">
	      <system>urn:oid:{string($contact/@code)}</system>
	      <value>{$contact/text()}</value>
	    </_>
	}
      </telecom>
      {
	for $address in ($organization/csd:demographic/csd:address[@type='Practice'])[1]
	return 
	   <address type="object">
	     <use>{string($address/@type)}</use>
	     <line type="array">
	       {
		 for $al in $address/csd:addressLine[@component = 'streetAddress']
		 return <_>{$al/text()}</_>
	       }
	     </line>
	     { 
	       for $city in ($address/csd:addressLine[@component = 'city'])[1]
	       return <city>{$city/text()}</city>
	     }
	     {
	       for $state in ($address/csd:addressLine[@component = 'stateProvince'])[1]
	       return <state>{$state/text()}</state>
	     }
	     {
	       for $zip in ($address/csd:addressLine[@component = 'postalCode'])[1]
	       return <zip>{$zip/text()}</zip>
	     }
	     {
	       for $country in ($address/csd:addressLine[@component = 'country'])[1]
	       return <country>{$country /text()}</country>
	     }
           </address>
      }
      {
	for $org in ($organization/csd:parent)[1]
	   (: Note: base for URL for reference should maybe be handled by stored function extension metadata   :)
	   return <partOf type="object"><reference>{string($org/@entityID)}</reference></partOf>
      }
      {
	if ($organization/csd:record/@status = '106-001')
        then <status>1</status>
        else <status>0</status>
      }
    </json>
    
  return 
    if ($as_xml) 
    then $xml
    else json:serialize($xml,map{"format":"direct"})  

};




(:
   Function to turn a CSD Provider entity into a FHIR Practitioner
:)

declare function fadpt:represent_provider_as_practitioner_JSON($doc,$provider) {
  fadpt:represent_provider_as_practitioner_JSON($doc,$provider,false())
};

declare function fadpt:represent_provider_as_practitioner_JSON($doc,$provider,$as_xml) 
{
  let $hapi := hapi:new()
  let $xml := fadpt:represent_provider_as_practitioner($doc,$provider)
  let $xml_string := serialize($xml)
  return  hapi:transform($hapi,$xml_string,"xml","Communication")
};






