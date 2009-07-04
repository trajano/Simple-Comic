//
//  TSSTManagedGroup.m
//  SimpleComic
//
//  Created by Alexander Rauchfuss on 6/2/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.



#import "TSSTManagedGroup.h"
#import "SimpleComicAppDelegate.h"
#import <XADMaster/XADArchive.h>
#import <Quartz/Quartz.h>
#import "TSSTImageUtilities.h"
#import "BDAlias.h"
#import "TSSTPage.h"

@implementation TSSTManagedGroup


@synthesize alias;


- (void)awakeFromInsert
{
	[super awakeFromInsert];
    groupLock = [NSLock new];
    instance = nil;
}


- (void)awakeFromFetch
{
	[super awakeFromFetch];
    groupLock = [NSLock new];
    instance = nil;
	NSData * aliasData = [self valueForKey: @"pathData"];
	
    if (aliasData != nil)
    {
        BDAlias * savedAlias = [[BDAlias alloc] initWithData: aliasData];
		[self setValue: savedAlias forKey: @"alias"];
		[savedAlias release];
    }
}


- (void)willTurnIntoFault
{
	if([[self valueForKey: @"nested"] boolValue])
	{
		[[NSFileManager defaultManager] removeFileAtPath: [self valueForKey: @"path"] handler: nil];
	}
}


- (void)didTurnIntoFault
{	
	[alias release];
    [groupLock release];
    [instance release];
	instance = nil;
	groupLock = nil;
}



- (void)setPath:(NSString *)newPath
{
	BDAlias * newAlias = [[BDAlias alloc] initWithPath: newPath];
	[self setValue: newAlias forKey: @"alias"];
	[self setValue: [newAlias aliasData] forKey: @"pathData"];
	[newAlias release];
}



- (NSString *)path
{
	NSString * hardPath = [[self valueForKey: @"alias"] fullPath];
	if(!hardPath)
	{
		[[self managedObjectContext] deleteObject: self];
	}
	return hardPath;
}



- (id)instance
{
    return nil;
}



- (NSData *)dataForPageIndex:(NSInteger)index
{
    return nil;
}


- (NSManagedObject *)topLevelGroup
{
	return self;
}


- (void)nestedFolderContents
{
	NSString * folderPath = [self valueForKey: @"path"];
	NSFileManager * fileManager = [NSFileManager defaultManager];
	NSManagedObject * nestedDescription;
	NSArray * nestedFiles = [fileManager directoryContentsAtPath: folderPath];
	NSString * path, * fileExtension, * fullPath;
	BOOL isDirectory, exists;
	
	for (path in nestedFiles)
	{
		nestedDescription = nil;
		fileExtension = [[path pathExtension] lowercaseString];
		fullPath = [folderPath stringByAppendingPathComponent: path];
		exists = [fileManager fileExistsAtPath: fullPath isDirectory: &isDirectory];
		if(exists && ![[[path lastPathComponent] substringToIndex: 1] isEqualToString: @"."])
		{
			if(isDirectory)
			{
				nestedDescription = [NSEntityDescription insertNewObjectForEntityForName: @"ImageGroup" inManagedObjectContext: [self managedObjectContext]];
			 	[nestedDescription setValue: fullPath forKey: @"path"];
		 		[nestedDescription setValue: path forKey: @"name"];
	 			[(TSSTManagedGroup *)nestedDescription nestedFolderContents];
			}
			else if([[TSSTManagedArchive archiveExtensions] containsObject: fileExtension])
			{
				nestedDescription = [NSEntityDescription insertNewObjectForEntityForName: @"Archive" inManagedObjectContext: [self managedObjectContext]];
				[nestedDescription setValue: fullPath forKey: @"path"];
				[nestedDescription setValue: path forKey: @"name"];
				[(TSSTManagedArchive *)nestedDescription nestedArchiveContents];
			}
			else if([fileExtension isEqualToString: @"pdf"])
 			{
				nestedDescription = [NSEntityDescription insertNewObjectForEntityForName: @"PDF" inManagedObjectContext: [self managedObjectContext]];
				[nestedDescription setValue: fullPath forKey: @"path"];
				[nestedDescription setValue: path forKey: @"name"];
				[(TSSTManagedPDF *)nestedDescription pdfContents];
			}
			else if([[TSSTPage imageExtensions] containsObject: fileExtension])
			{
				nestedDescription = [NSEntityDescription insertNewObjectForEntityForName: @"Image" inManagedObjectContext: [self managedObjectContext]];
				[nestedDescription setValue: fullPath forKey: @"imagePath"];
			}
			else if ([[TSSTPage textExtensions] containsObject: fileExtension])
			{
				nestedDescription = [NSEntityDescription insertNewObjectForEntityForName: @"Image" inManagedObjectContext: [self managedObjectContext]];
				[nestedDescription setValue: fullPath forKey: @"imagePath"];
				[nestedDescription setValue: [NSNumber numberWithBool: YES] forKey: @"text"];
			}
			if(nestedDescription)
			{
				[nestedDescription setValue: self forKey: @"group"];
			}
		}
	}
}


- (NSSet *)nestedImages
{
	NSMutableSet * allImages = [[NSMutableSet alloc] initWithSet: [self valueForKey: @"images"]];
	NSSet * groups = [self valueForKey: @"groups"];
	for(NSManagedObject * group in groups)
	{
		[allImages unionSet: [group valueForKey: @"nestedImages"]];
	}
	
	return [allImages autorelease];
}


@end

static NSArray * TSSTComicArchiveTypes = nil;


@implementation TSSTManagedArchive


+ (NSArray *)archiveExtensions
{
	if(!TSSTComicArchiveTypes)
	{
		TSSTComicArchiveTypes = [[NSArray arrayWithObjects: @"rar", @"cbr", @"zip", @"cbz", @"7z", @"lha", @"lzh", nil] retain];
	}
	
	return TSSTComicArchiveTypes;
}


- (void)willTurnIntoFault
{
	if([[self valueForKey: @"nested"] boolValue])
	{
		[[NSFileManager defaultManager] removeFileAtPath: [self valueForKey: @"path"] handler: nil];
	}
	
	NSString * solid  = [self valueForKey: @"solidDirectory"];
	if(solid)
	{
		[[NSFileManager defaultManager] removeFileAtPath: solid handler: nil];
	}
}



- (id)instance
{
    if (!instance)
    {
		NSFileManager * manager = [NSFileManager defaultManager];
		if([manager fileExistsAtPath: [self valueForKey: @"path"]])
		{
			instance = [[XADArchive alloc] initWithFile: [self valueForKey: @"path"]];
			// Set the archive delegate so that password and encoding queries can have a modal pop up.
			[instance setDelegate: [NSApp delegate]];
			
			if([self valueForKey: @"password"])
			{
				[instance setPassword: [self valueForKey: @"password"]];
			}
		}
    }
	
    return instance;
}



- (NSData *)dataForPageIndex:(NSInteger)index
{
	NSString * solidDirectory = [self valueForKey: @"solidDirectory"];
	NSData * imageData;
	if(!solidDirectory)
	{
		[groupLock lock];
		imageData = [[self instance] contentsOfEntry: index];
		[groupLock unlock];
	}
	else
	{
		NSString * name = [[self instance] nameOfEntry: index];
		NSString * fileName = [NSString stringWithFormat:@"%i.%@", index, [name pathExtension]];
		fileName = [solidDirectory stringByAppendingPathComponent: fileName];
		if(![[NSFileManager defaultManager] fileExistsAtPath: fileName])
		{
			[groupLock lock];
			imageData = [[self instance] contentsOfEntry: index];
			[groupLock unlock];
			[imageData writeToFile: fileName options: 0 error: nil];
		}
		else
		{
			imageData = [NSData dataWithContentsOfFile: fileName];
		}
	}

    return [[imageData retain] autorelease];
}



- (NSManagedObject *)topLevelGroup
{
	NSManagedObject * group = self;
	NSManagedObject * parentGroup = group;
	
	while(group)
	{
		group = [group valueForKeyPath: @"group"];
		parentGroup = group && [group class] == [TSSTManagedArchive class] ? group : parentGroup;
	}
	
	return parentGroup;
}



- (void)nestedArchiveContents
{
    XADArchive * imageArchive = [self valueForKey: @"instance"];
	
    if([imageArchive isEncrypted])
    {
        NSString * password = nil;
        NSData * testData = nil;
        do
		{
            password = [[NSApp delegate] passwordForArchiveWithPath: [self valueForKey: @"path"]];
            [imageArchive setPassword: password];
            testData = [self dataForPageIndex: 1];
        } while(password && !testData);
        
		if(!testData)
        {
            return;
        }
		
        [self setValue: password forKey: @"password"];
    }
    
    NSFileManager * fileManager = [NSFileManager defaultManager];
	NSData * fileData;
	int collision = 0;
    TSSTManagedGroup * nestedDescription;
    NSString * extension, * archivePath = nil;
	NSString * fileName = [self valueForKey: @"name"];
	int counter, archivedFilesCount = [imageArchive numberOfEntries];

	if([imageArchive isSolid])
	{
		do {
			archivePath = [NSString stringWithFormat: @"SC-images-%i", collision];
			archivePath = [NSTemporaryDirectory() stringByAppendingPathComponent: archivePath];
			++collision;
		} while (![fileManager createDirectoryAtPath: archivePath attributes: nil]);
		[self setValue: archivePath forKey: @"solidDirectory"];
	}
    
    for (counter = 0; counter < archivedFilesCount; ++counter)
    {
        fileName = [imageArchive nameOfEntry: counter];
        nestedDescription = nil;
		
        if(!([fileName isEqualToString: @""] || [[[fileName lastPathComponent] substringToIndex: 1] isEqualToString: @"."]))
        {
            extension = [[fileName pathExtension] lowercaseString];
            if([[TSSTPage imageExtensions] containsObject: extension])
            {
                nestedDescription = [NSEntityDescription insertNewObjectForEntityForName: @"Image" inManagedObjectContext: [self managedObjectContext]];
				[nestedDescription setValue: fileName forKey: @"imagePath"];
				[nestedDescription setValue: [NSNumber numberWithInt: counter] forKey: @"index"];
            }
            else if([[[NSUserDefaults standardUserDefaults] valueForKey: TSSTNestedArchives] boolValue] && [[TSSTManagedArchive archiveExtensions] containsObject: extension])
            {
				fileData = [imageArchive contentsOfEntry: counter];
				nestedDescription = [NSEntityDescription insertNewObjectForEntityForName: @"Archive" inManagedObjectContext: [self managedObjectContext]];
				[nestedDescription setValue: fileName forKey: @"name"];
				[nestedDescription setValue: [NSNumber numberWithBool: YES] forKey: @"nested"];
				
				collision = 0;
				do {
					archivePath = [NSString stringWithFormat: @"%i-%@", collision, fileName];
					archivePath = [NSTemporaryDirectory() stringByAppendingPathComponent: archivePath];
					++collision;
				} while ([fileManager fileExistsAtPath: archivePath]);
				
				[fileData writeToFile: archivePath atomically: YES];
				[nestedDescription setValue: archivePath forKey: @"path"];
				[(TSSTManagedArchive *)nestedDescription nestedArchiveContents];
            }
			else if([[TSSTPage textExtensions] containsObject: extension])
			{
				nestedDescription = [NSEntityDescription insertNewObjectForEntityForName: @"Image" inManagedObjectContext: [self managedObjectContext]];
				[nestedDescription setValue: fileName forKey: @"imagePath"];
				[nestedDescription setValue: [NSNumber numberWithInt: counter] forKey: @"index"];
				[nestedDescription setValue: [NSNumber numberWithBool: YES] forKey: @"text"];
			}
            else if([extension isEqualToString: @"pdf"])
            {
                nestedDescription = [NSEntityDescription insertNewObjectForEntityForName: @"PDF" inManagedObjectContext: [self managedObjectContext]];
                archivePath = [NSTemporaryDirectory() stringByAppendingPathComponent: fileName];
                int collision = 0;
                while([fileManager fileExistsAtPath: archivePath])
                {
                    ++collision;
                    fileName = [NSString stringWithFormat: @"%i-%@", collision, fileName];
                    archivePath = [NSTemporaryDirectory() stringByAppendingPathComponent: fileName];
                }
                [imageArchive extractEntry: counter to: NSTemporaryDirectory() withName: fileName];
                [nestedDescription setValue: archivePath forKey: @"path"];
                [nestedDescription setValue: [NSNumber numberWithBool: YES] forKey: @"nested"];
				[(TSSTManagedPDF *)nestedDescription pdfContents];
            }
			
			if(nestedDescription)
			{
				[nestedDescription setValue: self forKey: @"group"];
			}
        }
    }
}



@end


@implementation TSSTManagedPDF


- (id)instance
{
    if (!instance)
    {
        instance = [[PDFDocument alloc] initWithData: [NSData dataWithContentsOfFile: [self valueForKey: @"path"]]];
    }
	
    return instance;
}



- (NSData *)dataForPageIndex:(NSInteger)index
{	
    [groupLock lock];
	PDFPage * page = [[self instance] pageAtIndex: index];
    [groupLock unlock];
	
	NSRect bounds = [page boundsForBox: kPDFDisplayBoxMediaBox];
	float dimension = 1400;
	float scale = 1 > (NSHeight(bounds) / NSWidth(bounds)) ? dimension / NSWidth(bounds) :  dimension / NSHeight(bounds);
	bounds.size = scaleSize(bounds.size, scale);
	
	NSImage * pageImage = [[NSImage alloc] initWithSize: bounds.size];
	[pageImage lockFocus];
		[[NSColor whiteColor] set];
		NSRectFill(bounds );
		NSAffineTransform * scaleTransform = [NSAffineTransform transform];
		[scaleTransform scaleBy: scale];
		[scaleTransform concat];
		[page drawWithBox: kPDFDisplayBoxMediaBox];
	[pageImage unlockFocus];
	
	NSData * imageData = [[pageImage TIFFRepresentation] retain];
	[pageImage release];
	
    return [imageData autorelease];
}


/*  Creates an image managedobject for every "page" in a pdf. */
- (void)pdfContents
{
    NSPDFImageRep * rep = [self instance];
    TSSTPage * imageDescription;
    NSMutableSet * pageSet = [NSMutableSet set];
    int imageCount = [rep pageCount];
    int pageNumber;
    for (pageNumber = 0; pageNumber < imageCount; ++pageNumber)
    {
        imageDescription = [NSEntityDescription insertNewObjectForEntityForName: @"Image" inManagedObjectContext: [self managedObjectContext]];
        [imageDescription setValue: [NSString stringWithFormat: @"%i", pageNumber + 1] forKey: @"imagePath"];
        [imageDescription setValue: [NSNumber numberWithInt: pageNumber] forKey: @"index"];
        [pageSet addObject: imageDescription];
    }
	[self setValue: pageSet forKey: @"images"];
}


@end
