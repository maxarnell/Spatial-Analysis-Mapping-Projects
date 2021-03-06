/****** Script for SelectTopNRows command from SSMS  ******/
      
--===========================================================================================================================
-- Remove duplicate records from FSP dataset, and filter based on date and time, and create FSP incident view from selection
--===========================================================================================================================

CREATE VIEW MOTM_FSP_2017_ASSISTS_ND as 
SELECT DISTINCT
[Date],[Incident_Time], [IncidentID], [CHPIncidentType],[Lat],[Lon]
FROM [dbo].[MOTM_FSP_2017_ASSISTS] 
WHERE 
(IncidentID IS NOT NULL)
AND 
(Incident_Time IS NOT NULL AND [Date] is not null)
AND 
([Date] BETWEEN '2017-01-24' AND '2017-03-10')
AND
(( CAST(Incident_Time as TIME) BETWEEN '06:00' AND '10:00') or ( CAST(Incident_Time as TIME) BETWEEN '15:00' AND '19:00'))

--===========================================================================================================================
-- Filter Waze data to include records with a given reliability score and incident type. 
-- Filter based on date and time, and create WAZE incident view from selection 
--===========================================================================================================================

--DROP VIEW MOTM_WAZE_INCIDENTS_FILTERED

CREATE VIEW MOTM_WAZE_INCIDENTS_FT as 
SELECT * 
FROM [dbo].[MOTM_WAZE_RSS_FEED]
WHERE 
((type IN ( 'ACCIDENT','WEATHERHAZARD')) AND subtype IN ('ACCIDENT_MAJOR', 'ACCIDENT_MINOR', 'HAZARD_ON_ROAD', 'HAZARD_ON_ROAD_CAR_STOPPED', 'HAZARD_ON_ROAD_OBJECT', 'HAZARD_ON_SHOULDER', 'HAZARD_ON_SHOULDER_CAR_STOPPED'))
AND 
([dateAdded] BETWEEN '2017-01-24' AND '2017-03-10')
AND 
((CAST([dateAdded] as TIME) BETWEEN '6:00' AND '10:00') or (CAST([dateAdded] as TIME) BETWEEN '15:00' AND '19:00'))
AND 
[reliability] >= 7

--===========================================================================================================================
--**********************************ARCGIS PRO GEOPROCESSING*****************************************************************
/*
1. In ArcGIS Pro, Make XY Event Layers from the previously created views: 
	MOTM_FSP_2017_ASSISTS_ND, 
	MOTM_WAZE_INCIDENTS_FT
2. Create Feature Class from each xy event layer, projected to UTM Zone 10N, save as:
	MOTM_FSP_2017_ASSISTS_ND_FC, 
	MOTM_WAZE_INCIDENTS_FT_FC
3. Select each of the newly created feature classes within 100FT of Freeways, save as: 
	MOTM_FSP_2017_ASSISTS_ND_100FT_FREEWAY, 
	MOTM_WAZE_INCIDENTS_FT_100FT_FREEWAY 
4. Run near function on both of the previous feature classes, renaming 'NEAR_FID' TO 'CF_FID' 
	For FSP data, select aggregate points along Bay Area Freeways along existing FSP beats then run near function
		-this step ensures that FSP incidents are only associated with aggregate points that are along FSP beat
*/
--===========================================================================================================================

--===========================================================================================================================
-- ALTER CF Table to include columns for WAZE Incident Count, FSP Incident Count, Total Incidents, Share of Total 
-- for WAZE Incidents, and Share of Total for FSP Incidents 
--===========================================================================================================================

ALTER TABLE [dbo].[CF_SUMMARY_PNTS]
ADD 
	WAZE_Incident_Count INT, 
	FSP_Incident_Count INT, 
	Total_Incidents INT, 
	WAZE_SOT decimal(5,2), 
	FSP_SOT decimal(5,2)  

--===========================================================================================================================
-- UPDATE CF Table set values for WAZE Incident Count, FSP Incident Count, Total Incident, Share of Total 
-- for WAZE Incident, and Share of Total for FSP Incident Columns
--===========================================================================================================================

UPDATE CF 
SET 
	CF.[WAZE_Incident_Count] = ISNULL(WAZE.WAZE_Incident_Count, 0),
	CF.[FSP_Incident_Count] = ISNULL(FSP.FSP_Incident_Count, 0),
	CF.[Total_Incidents] = (ISNULL(WAZE.WAZE_Incident_Count, 0) + ISNULL(FSP.FSP_Incident_Count, 0)), 
	CF.[WAZE_SOT] = 
	CASE 
		WHEN (ISNULL(WAZE.WAZE_Incident_Count, 0) + ISNULL(FSP.FSP_Incident_Count, 0)) > 0 
			THEN ((ISNULL(CAST(WAZE.WAZE_Incident_Count AS FLOAT), 0) / (ISNULL(CAST(WAZE.WAZE_Incident_Count AS FLOAT), 0) + ISNULL(CAST(FSP.FSP_Incident_Count AS FLOAT), 0))) * 100)
		ELSE 
			0
	END,
	CF.[FSP_SOT] = 
	CASE 
		WHEN (ISNULL(WAZE.WAZE_Incident_Count, 0) + ISNULL(FSP.FSP_Incident_Count, 0)) > 0 
			THEN ((ISNULL(CAST(FSP.FSP_Incident_Count AS FLOAT), 0) / (ISNULL(CAST(WAZE.WAZE_Incident_Count AS FLOAT), 0) + ISNULL(CAST(FSP.FSP_Incident_Count AS FLOAT), 0))) * 100)
		ELSE 
			0
	END 
FROM [dbo].[CF_SUMMARY_PNTS] AS CF 
LEFT JOIN 
(
	SELECT [CF_FID],COUNT(*) AS WAZE_Incident_Count
	FROM [dbo].[MOTM_WAZE_INCIDENTS_FT_100FT_FREEWAY]
	GROUP BY CF_FID 
) AS WAZE 
ON WAZE.[CF_FID] = CF.[OBJECTID]
LEFT JOIN 
(
	SELECT [CF_FID],COUNT(*) AS FSP_Incident_Count
	FROM [dbo].[MOTM_FSP_2017_ASSISTS_ND_100FT_FREEWAY]
	GROUP BY CF_FID 
) AS FSP 
ON FSP.[CF_FID] = CF.[OBJECTID] 

--===========================================================================================================================
-- UPDATE CF Table set values for CountyFIP using spatial join with counties (this updates CF points that did not have 
-- county FIP already assigned because they are newly created points. 
--===========================================================================================================================

UPDATE CF
SET CF.[CountyFIP] = CT.CountyFIP
FROM [dbo].[CF_SUMMARY_PNTS] AS CF 
JOIN [dbo].[MOTM_MN_A1_BAYAREA_PROJ] AS CT
ON CF.Shape.STIntersects(CT.Shape) = 1

--===========================================================================================================================
-- Create summary of incidents by county for charting purposes 
--===========================================================================================================================

SELECT [CountyFIP], SUM([WAZE_Incident_Count]) as WAZE_Incident_County, SUM([FSP_Incident_Count]) as FSP_Incident_Count, SUM([Total_Incidents]) AS Total_Incidents 
FROM [dbo].[CF_SUMMARY_PNTS]
GROUP BY CountyFIP
ORDER BY CountyFIP ASC 