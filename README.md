# Build-NTNXVM-CatalogItem
Build a Nutanix VM based on a Catalog Item

The json is pulled by leveraging developer tools in the browser during creation of a VM using a catalog item.  You can adjust the UUIDs as needed for your purposes.  
In my case, all clusters are not added to Prism Central and I want to ensure we don't have duplicate names.  Lastly, I wait for the VM to complete being created and then 
I adjust the timezone as is appropriate for me.
