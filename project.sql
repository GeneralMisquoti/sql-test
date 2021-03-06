-- ==========================
--    Prequels Database
-- =========================
-- By Jakub Koralewski

-- -------------------------
-- Database - creating
-- Comment this script part, if you run the script on the faculty MSSQL server.
-- -------------------------
--USE master
--GO

IF DB_ID('PrequelsDatabase') IS NULL
CREATE DATABASE PrequelsDatabase
GO

USE PrequelsDatabase
GO

-- ------------------------------------------------------
-- Tables - deleting (in reverse order to create!)
-- ------------------------------------------------------
IF OBJECT_ID('Fights', 'U') IS NOT NULL
    DROP TABLE Fights

IF OBJECT_ID('MasterApprenticeRelations', 'U') IS NOT NULL
    DROP TABLE MasterApprenticeRelations

IF OBJECT_ID('DialogueStats', 'U') IS NOT NULL
    DROP TABLE DialogueStats

IF OBJECT_ID('Dialogue', 'U') IS NOT NULL
    DROP TABLE Dialogue

IF OBJECT_ID('CharactersMoviesRelations', 'U') IS NOT NULL
    DROP TABLE CharactersMoviesRelations

IF OBJECT_ID('Characters', 'U') IS NOT NULL
    DROP TABLE Characters

IF OBJECT_ID('Planets', 'U') IS NOT NULL
    DROP TABLE Planets

IF OBJECT_ID('Movies', 'U') IS NOT NULL DROP TABLE Movies

-- --------------------------------
-- Tables - creating
-- --------------------------------
IF OBJECT_ID('Movies', 'U') IS NULL
CREATE TABLE Movies
(
    PartID      TINYINT PRIMARY KEY,
    Name        VARCHAR(50) NOT NULL UNIQUE,
    ReleaseDate DATE        NOT NULL UNIQUE,
    Budget      BIGINT      NOT NULL,
    BoxOffice   BIGINT      NOT NULL,
    WordsSpoken INT NOT NULL, -- in general (even characters not included in tables)
    WordsSpokenByCharacters INT -- generated from dialogue table
)
IF OBJECT_ID('GetNumWordsFromLine', 'FN') IS NOT NULL
    DROP FUNCTION GetNumWordsFromLine
GO

CREATE FUNCTION GetNumWordsFromLine(
    @line VARCHAR(586)
) RETURNS INT
BEGIN
    RETURN LEN(@line) - LEN(REPLACE(@line, ' ', '')) + 1
END
GO

IF OBJECT_ID('Planets', 'U') IS NULL
CREATE TABLE Planets
(
    ID         INT PRIMARY KEY IDENTITY (0, 1),
    Name       VARCHAR(20) NOT NULL UNIQUE,
    NumSuns    INT DEFAULT 1, --
    NumMoons   INT DEFAULT 1,
    Population BIGINT
)
IF OBJECT_ID('Characters', 'U') IS NULL
CREATE TABLE Characters
(
    ID            INT PRIMARY KEY IDENTITY (0,1),
    Name          NVARCHAR(50) NOT NULL UNIQUE,                            -- NVARCHAR for unicode characters
    Midichlorians INT DEFAULT 0,
    PlayedBy      VARCHAR(50),
    LikesSand     BIT,                                                     -- YES/NO/N-A = 1/0/NULL
    FromPlanet    INT          REFERENCES Planets (ID) ON DELETE SET NULL, -- NULL if unknown
    Jedi          BIT DEFAULT NULL,                                        -- JEDI/SITH/NONE = 1/0/NULL (at time of death)
)
-- ------
-- which characters play in which movies
-- ------
IF OBJECT_ID('CharactersMoviesRelations', 'U') IS NULL
CREATE TABLE CharactersMoviesRelations
(
    RelationID     INT     PRIMARY KEY IDENTITY(0, 1),
    CharacterID    INT     NOT NULL REFERENCES Characters (ID) ON DELETE CASCADE,
    MovieID        TINYINT NOT NULL REFERENCES Movies (PartID) ON DELETE CASCADE,
    NumWordsSpoken INT,                                    -- number of words spoken in that movie

    CONSTRAINT CMR_NoRepeats UNIQUE (CharacterID, MovieID) -- no repeats
)
IF OBJECT_ID('GenerateCharactersMoviesRelations', 'P') IS NOT NULL
    DROP PROCEDURE GenerateCharactersMoviesRelations
GO


-- --------
-- transactional
-- --------
IF OBJECT_ID('Dialogue', 'U') IS NULL
CREATE TABLE Dialogue
(
    ID       INT PRIMARY KEY IDENTITY (0,1),
    Movie    TINYINT      NOT NULL REFERENCES Movies (PartID) ON DELETE CASCADE,
    FromID   INT          NOT NULL REFERENCES Characters (ID) ON DELETE CASCADE,-- speaking to yourself allowed
    ToID     INT REFERENCES Characters (ID),
    Dialogue VARCHAR(586) NOT NULL,
    WordCount INT
)
GO

CREATE PROCEDURE GenerateCharactersMoviesRelations AS
INSERT INTO CharactersMoviesRelations (CharacterID, MovieID, NumWordsSpoken)
SELECT FromId,
       Movie,
       SUM(dbo.GetNumWordsFromLine(Dialogue))
  FROM Dialogue d
 GROUP BY d.FromID, d.Movie
GO

IF OBJECT_ID('GenerateWordsSpokenPerLine', 'P') IS NOT NULL
    DROP PROCEDURE GenerateWordsSpokenPerLine
GO

CREATE PROCEDURE GenerateWordsSpokenPerLine AS
UPDATE Dialogue
   SET WordCount = WordCountGenerated
       FROM Dialogue d
       INNER JOIN (SELECT ID, WordCountGenerated=dbo.GetNumWordsFromLine(Dialogue) FROM Dialogue) d2
        ON d.ID=d2.ID
GO

IF OBJECT_ID('GenerateWordsSpokenPerMovie', 'P') IS NOT NULL
    DROP PROCEDURE GenerateWordsSpokenPerMovie
GO

CREATE PROCEDURE GenerateWordsSpokenPerMovie AS
UPDATE Movies
   SET WordsSpokenByCharacters = WordsSpokenPerMovie
  FROM Movies m
      INNER JOIN (
          SELECT Movie, WordsSpokenPerMovie=SUM(WordCount) FROM Dialogue d GROUP BY Movie
      ) g
      ON g.Movie=m.PartID
GO


IF OBJECT_ID('DialogueStats', 'U') IS NULL
CREATE TABLE DialogueStats
(
    FromID   INT NOT NULL REFERENCES Characters (ID) ON DELETE CASCADE,-- speaking to yourself allowed
    ToID     INT REFERENCES Characters (ID),                           -- null since can speak to multiple, or unknown people
    NumWords INT NOT NULL,                                             -- if words is 0 then doesn't need to be in the table

    CONSTRAINT DS_NoRepeats UNIQUE (FromID, ToID)                      -- no repeats
)
GO

IF OBJECT_ID('GenerateDialogueStats', 'P') IS NOT NULL
    DROP PROCEDURE GenerateDialogueStats
GO

CREATE PROCEDURE GenerateDialogueStats AS
INSERT INTO DialogueStats
SELECT FromId,
       ToID,
       NumWords = (
           SELECT SUM(WordCount)
             FROM Dialogue
            WHERE FromID = d.FromID
              AND ToID = d.ToID
       )
  FROM Dialogue d
 GROUP BY d.FromID, d.ToID
GO

IF OBJECT_ID('MasterApprenticeRelations', 'U') IS NULL
CREATE TABLE MasterApprenticeRelations
(
    MasterID     INT REFERENCES Characters (ID),
    ApprenticeID INT REFERENCES Characters (ID),
    CONSTRAINT MA_DifferentIDS CHECK (MasterID != ApprenticeID), -- being your own master not allowed CONSTRAINT MA_NoRepeats UNIQUE (MasterID, ApprenticeID)      -- no repeats
)
-- -------
-- Lightsaber Duels https://youtu.be/esnMDtMysHo?t=402
-- (Winner: 0 if first is winner, 1 if second is winner, NULL if tie/unknown, e.g.: Obi-Wan fought Anakin in 6th part, Obi-Wan objectively won).
-- -------
IF OBJECT_ID('Fights', 'U') IS NULL
CREATE TABLE Fights
(
    ID              INT PRIMARY KEY,                                                  -- index
    FightID         INT     NOT NULL,                                                 -- ID can repeat (multiple people can be in the same fight!)
    MovieID         TINYINT NOT NULL REFERENCES Movies (PartID) ON DELETE CASCADE,
    FirstFighterID  INT     NOT NULL REFERENCES Characters (ID) ON DELETE CASCADE,
    SecondFighterID INT     NOT NULL REFERENCES Characters (ID),
    Winner          BIT,                                                              -- 1/0/NULL = First/Second/Unknown-or-Tie

    CONSTRAINT F_NoRepeats UNIQUE (FightID, MovieID, FirstFighterID, SecondFighterID) -- multiple people in same fight, but no repeats
)
-- ---------------------------------
-- test data
-- ---------------------------------
INSERT INTO Movies (PartID, Name, ReleaseDate, Budget, BoxOffice, WordsSpoken, WordsSpokenByCharacters)
VALUES (4, 'Phantom Menace', '1999/05/16', 115000000, 1027000000, 9132, NULL),      -- https://en.wikipedia.org/wiki/Star_Wars:_Episode_I_%E2%80%93_The_Phantom_Menace
       (5, 'Attack of the Clones', '2002/05/16', 115000000, 653000000, 7981, NULL), -- https://en.wikipedia.org/wiki/Star_Wars:_Episode_II_%E2%80%93_Attack_of_the_Clones
       (6, 'Revenge of the Sith', '2005/05/19', 113000000, 868400000, 7293, NULL) -- https://en.wikipedia.org/wiki/Star_Wars:_Episode_III_%E2%80%93_Revenge_of_the_Sith


SET IDENTITY_INSERT Planets ON;
INSERT INTO Planets (ID, Name, NumSuns, NumMoons, Population)
VALUES
    -- https://starwars.fandom.com/wiki/Coruscant
    (0, 'Coruscant', 1, 4, 1000000000000),
    -- https://starwars.fandom.com/wiki/Naboo
    (1, 'Naboo', 1, 3, 4500000000),
    -- https://starwars.fandom.com/wiki/Tatooine
    (2, 'Tatooine', 2, 3, 200000),
    -- https://starwars.fandom.com/wiki/Stewjon
    (3, 'Stewjon', NULL, NULL, NULL), -- unknown
    -- https://starwars.fandom.com/wiki/Serenno
    (4, 'Serenno', 1, 2, 4000000000000),
    -- https://starwars.fandom.com/wiki/Dathomir
    (5, 'Dathomir', 1, 2, 600),
    -- https://starwars.fandom.com/wiki/Haruun_Kal
    (6, 'Haruun Kal', 1, 1, NULL),
    -- https://starwars.fandom.com/wiki/Kalee
    (7, 'Kalee', 1, 1, NULL)
SET IDENTITY_INSERT Planets OFF;


SET IDENTITY_INSERT Characters ON;
-- Midichlorians source: http://starwarsuniverse2.tripod.com/id9.html
INSERT INTO Characters (ID, Name, Midichlorians, PlayedBy, LikesSand, FromPlanet, Jedi)
VALUES
    -- https://starwars.fandom.com/wiki/Qui-Gon_Jinn
    (0, 'Qui-Gon Jinn', 10000, 'Liam Neeson', 0, 0, 1), -- Dooku
    -- https://starwars.fandom.com/wiki/Darth_Sidious https://en.wikipedia.org/wiki/Palpatine
    (1, 'Sheev Palpatine', 20500, 'Ian McDiarmid', 1, 1, 0),
    -- https://starwars.fandom.com/wiki/Anakin_Skywalker https://en.wikipedia.org/wiki/Darth_Vader
    (2, 'Anakin Skywalker', 27700, 'Hayden Christensen', 0, 2, 1),
    -- https://starwars.fandom.com/wiki/Obi-Wan_Kenobi https://en.wikipedia.org/wiki/Obi-Wan_Kenobi
    (3, 'Obi-Wan Kenobi', 13400, 'Ewan McGregor', 1, 3, 1),
    -- https://starwars.fandom.com/wiki/Dooku https://en.wikipedia.org/wiki/Count_Dooku
    (4, 'Dooku', 13500, 'Christopher Lee', 1, 4, 0),
    -- https://starwars.fandom.com/wiki/Maul https://en.wikipedia.org/wiki/Darth_Maul
    (5, 'Maul', 12000, 'Ray Park', 1, 5, 0),
    -- https://starwars.fandom.com/wiki/Padm%C3%A9_Amidala
    (6, N'Padmé Amidala', 4700, 'Natalie Portman', 1, 1, NULL),
    -- https://starwars.fandom.com/wiki/Yoda https://en.wikipedia.org/wiki/Yoda
    (7, 'Yoda', 17700, 'Frank Oz', 1, NULL, 1),
    -- https://starwars.fandom.com/wiki/Mace_Windu https://en.wikipedia.org/wiki/Mace_Windu
    (8, 'Mace Windu', 12000, 'Samuel L. Jackson', 1, 6, 1),
    -- https://starwars.fandom.com/wiki/Grievous https://en.wikipedia.org/wiki/General_Grievous
    (9, 'General Grievous', 11900, 'Matthew Wood', 1, 7, NULL) -- not a sith
SET IDENTITY_INSERT Characters OFF;


INSERT INTO MasterApprenticeRelations
VALUES (0, 2), -- QG -> Anakin
       (0, 3), -- QG -> Obi
       (3, 2), -- Obi -> Anakin
       (1, 2), -- DS -> DV
       (1, 4), -- DS -> Dooku
       (1, 5), -- DS -> Maul
       (4, 0), -- Dooku -> QG
       (7, 3), -- Yoda -> Obi
       (7, 4), -- Yoda -> Dooku
       (7, 8), -- Yoda -> Mace Windu
       (4, 8) -- Dooku -> Grievous


IF OBJECT_ID('GetNumberOfCharactersInCMR', 'FN') IS NOT NULL
    DROP FUNCTION GetNumberOfCharactersInCMR
GO

CREATE FUNCTION GetNumberOfCharactersInCMR(
)
    RETURNS INT AS
BEGIN
    RETURN (
        SELECT COUNT(ID)
          FROM Characters
                   INNER JOIN
               CharactersMoviesRelations CMR ON Characters.ID = CMR.CharacterID
    )

END
GO

ALTER TABLE CharactersMoviesRelations
    ADD CONSTRAINT CMR_AllCharactersHaveRelations
        CHECK (dbo.GetNumberOfCharactersInCMR() != 0)


INSERT INTO Fights (ID, FightID, MovieID, FirstFighterID, SecondFighterID, Winner)
VALUES -- 4
       (0, 0, 4, 0, 5, NULL),  -- QG vs Maul - QG escapes -> tie
       (1, 1, 4, 5, 0, 1),     -- QG(&Obi) vs Maul - QG loses v Maul
       (2, 1, 4, 3, 5, 1),     -- Obi(&ded QG) - Obi wins v Maul
       -- 5
       (3, 2, 5, 4, 3, 1),     -- Obi(&Anakin) vs Dooku - Dooku almost kills Obi
       (4, 2, 5, 4, 2, 1),     -- Anakin(&Obi) vs Dooku - Anakin loses hand
       (5, 2, 5, 4, 7, NULL),  -- Yoda vs Dooku - Dooku escapes -> tie
       -- 6
       (6, 3, 6, 2, 4, 1),     -- Anakin(&Obi) vs Dooku -- Anakin decapitates Dooku
       (7, 3, 6, 4, 3, 1),     -- Obi(&Anakin) vs Dooku -- Obi unconscious
       (8, 4, 6, 3, 8, NULL),  -- Obi vs Grievous -- Grievous escapes
       (9, 5, 6, 1, 8, 1),     -- Palpatine vs Windu -- Palpatine wins (almost!)
       (10, 5, 6, 2, 8, 1),    -- Anakin vs Windu -- Anakin helps kill Windu
       (11, 6, 6, 7, 1, NULL), -- Yoda vs Palpatine
       (12, 7, 6, 3, 2, 1) -- Obi vs Anakin -- Obi has the high ground
GO

INSERT INTO Dialogue (Movie, FromID, ToID, Dialogue)
VALUES
(4,3,0,'I have a bad feeling about this.'),(4,0,3,'I don''t sense anything.'),(4,3,0,'It''s not about the mission, Master. It''s something elsewhere, elusive.'),(4,0,3,'Don''t center on your anxieties, Obi-Wan. Keep your concentration here and now, where it belongs.'),(4,3,0,'But Master Yoda said I should be mindful of the future.'),(4,0,3,'But not at the expense of the moment. Be mindful of the living Force, young Padawan.'),(4,3,0,'Yes, Master. How do you think this trade viceroy will deal with the chancellor''s demands?'),(4,0,3,'These Federation types are cowards. The negotiations will be short.'),(4,3,0,'Is it in their nature to make us wait this long?'),(4,0,3,'No. I sense an unusual amount of fear... for something as trivial as this trade dispute.'),(4,0,3,'Dioxis.'),(4,3,0,'Master! Destroyers! They have shield generators!'),(4,0,3,'It''s a standoff. Let''s go.'),(4,0,3,'Battle droids.'),(4,3,0,'It''s an invasion army.'),(4,0,3,'This is an odd play for the Trade Federation. We''ve got to warn the Naboo and contact Chancellor Valorum. Let''s split up. Stow aboard separate ships and meet down on the planet.'),(4,3,0,'You were right about one thing, Master. The negotiations were short.'),(4,6,1,'Senator Palpatine. What''s happening?'),(4,3,0,'What''s this?'),(4,0,3,'A local. Let''s get out of here before more droids show up.'),(4,3,0,'Master, what''s a bongo?'),(4,0,3,'A transport, I hope.'),(4,3,0,'Master, we''re short on time.'),(4,0,3,'We''ll need a navigator to get us through the planet''s core. This Gungan may be of help.'),(4,0,3,'There''s always a bigger fish.'),(4,3,0,'We''re losing power.'),(4,3,0,'Power''s back.'),(4,3,0,'You overdid it.'),(4,0,3,'Head for that outcropping.'),(4,3,0,'We''re losing droids fast.'),(4,3,0,'Here, Master. Tatooine. It''s small, out of the way, poor. The Trade Federation have no presence there.'),(4,3,0,'There''s a settlement.'),(4,3,0,'The hyperdrive generator''s gone, Master. We''ll need a new one.'),(4,0,3,'That''ll complicate things. Be wary. I sense a disturbance in the Force.'),(4,3,0,'I feel it also, Master.'),(4,0,3,'Don''t let them send any transmissions.'),(4,0,6,'Stay close to me.'),(4,0,6,'Moisture farms, for the most part. Some indigenous tribes and scavengers. The few spaceports like this one... are havens for those that don''t wish to be found.'),(4,6,0,'Like us.'),(4,0,6,'We''ll try one of the smaller dealers.'),(4,2,6,'Are you an angel?'),(4,6,2,'What?'),(4,2,6,'An angel. I heard the deep space pilots talk about them. They''re the most beautiful creatures in the universe. They live on the moons of lego,'),(4,2,6,'I think.'),(4,6,2,'You''re a funny little boy. How do you know so much?'),(4,2,6,'I listen to all the traders and star pilots who come through here. I''m a pilot, you know, and someday I''m gonna fly away from this place.'),(4,6,2,'You''re a pilot?'),(4,2,6,'Mm-hmm. All my life.'),(4,6,2,'How long have you been here?'),(4,2,6,'Since I was very little. Three, I think. My mom and I were sold to Gardulla the Hutt... but she lost us betting on the podraces.'),(4,6,2,'You''re a slave?'),(4,2,6,'I''m a person, and my name is Anakin.'),(4,6,2,'I''m sorry. I don''t fully understand. This is a strange place to me.'),(4,2,6,'Wouldn''t have lasted long anyways if I wasn''t so good at building things.'),(4,0,6,'We''re leaving.'),(4,6,2,'I''m glad to have met you, Anakin.'),(4,2,6,'I was glad to meet you too.'),(4,0,3,'And you''re sure there''s nothing left on board?'),(4,3,0,'A few containers of supplies. The queen''s wardrobe, maybe, but not enough for you to barter with... not in the amount you''re talking about.'),(4,0,3,'All right. I''m sure another solution will present itself. I''ll check back later.'),(4,2,0,'Hi.'),(4,0,2,'Hi there.'),(4,2,0,'Your buddy here was about to be turned into orange goo. He picked a fight with a Dug... an especially dangerous Dug called Sebulba.'),(4,0,2,'Thanks, my young friend.'),(4,2,0,'Here, you''ll like these pallies. Here.'),(4,0,2,'Thank you.'),(4,2,0,'Do you have shelter?'),(4,0,2,'We''ll head back to our ship.'),(4,2,0,'Is it far?'),(4,0,2,'It''s on the outskirts.'),(4,2,0,'You''ll never reach the outskirts in time. Sandstorms are very, very dangerous. Come on. I''ll take you to my place.'),(4,2,6,'I''m building a droid. You wanna see?'),(4,2,6,'Come on. I''ll show you Threepio.'),(4,2,6,'Isn''t he great? He''s not finished yet.'),(4,6,2,'He''s wonderful.'),(4,2,6,'You really like him? He''s a protocol droid to help Mom. Watch.'),(4,2,2,'Whoops.'),(4,6,2,'He''s perfect.'),(4,2,6,'When the storm is over, I''ll show you my racer. I''m building a Podracer.'),(4,1,0,'The death toll is catastrophic. We must bow to their wishes. You must contact me.'),(4,0,3,'It sounds like bait to establish a connection trace.'),(4,3,0,'What if it is true, and the people are dying?'),(4,0,3,'Either way, we''re running out of time.'),(4,5,1,'Tatooine is sparsely populated. If the trace was correct, I will fnd them quickly, Master.'),(4,1,5,'Move against the Jedi first. You will then have no difficulty in taking the queen to Naboo... to sign the treaty.'),(4,5,1,'At last we will reveal ourselves to the Jedi. At last we will have revenge.'),(4,1,5,'You have been well-trained, my young apprentice. They will be no match for you.'),(4,2,0,'I''ve been working on a scanner to try and locate mine.'),(4,2,0,'And they blow you up! Boom!'),(4,6,2,'I can''t believe there''s still slavery in the galaxy. The Republic''s antislavery laws...'),(4,2,0,'Has anybody ever seen a Podrace?'),(4,0,2,'They have Podracing on Malastare. Very fast, very dangerous.'),(4,2,0,'I''m the only human who can do it.'),(4,0,2,'You must have Jedi reflexes if you race pods.'),(4,2,0,'You''re a Jedi knight, aren''t you?'),(4,0,2,'What makes you think that?'),(4,2,0,'I saw your laser sword. Only Jedis carry that kind of weapon.'),(4,0,2,'Perhaps I killed a Jedi and took it from him.'),(4,2,0,'I don''t think so. No one can kill a Jedi.'),(4,0,2,'I wish that were so.'),(4,2,0,'I had a dream I was a Jedi. I came back here and freed all the slaves.'),(4,2,0,'Have you come to free us?'),(4,0,2,'No, I''m afraid not.'),(4,2,0,'I think you have. Why else would you be here?'),(4,0,2,'I can see there''s no fooling you, Anakin.'),(4,0,2,'We''re on our way to Coruscant, the central system in the Republic... on a very important mission.'),(4,2,0,'How did you end up out here in the outer rim?'),(4,6,2,'Our ship was damaged, and we''re stranded here until we can repair it.'),(4,2,0,'I can help. I can fix anything.'),(4,0,2,'I believe you can. But first we must acquire the parts we need.'),(4,6,0,'These junk dealers must have a weakness of some kind.'),(4,2,0,'I built a racer. It''s the fastest ever. There''s a big race tomorrow on Boonta Eve.'),(4,2,0,'You could enter my pod.'),(4,0,2,'Your mother''s right.'),(4,0,2,'Is there anyone friendly to the Republic who can help us?'),(4,6,0,'Are you sure about this? Trusting our fate to a boy we hardly know? The queen will not approve.'),(4,0,6,'The queen doesn''t need to know.'),(4,6,0,'Well, I don''t approve.'),(4,2,0,'It wasn''t my fault. Really. Sebulba flashed me with his vents. I actually saved the pod, mostly.'),(4,3,0,'What if this plan fails, Master? We could be stuck here a very long time.'),(4,0,3,'Well, it''s too dangerous to call for help... and a ship without a power supply isn''t going to get us anywhere. And... there''s something about this boy.'),(4,0,2,'I think it''s time we found out.'),(4,0,2,'Here, use this power charge.'),(4,2,0,'Yes, sir!'),(4,2,0,'It''s working! It''s working!'),(4,0,2,'Stay still, Ani. Let me clean this cut.'),(4,2,0,'There''s so many. Do they all have a system of planets?'),(4,0,2,'Most of them.'),(4,2,0,'Has anyone been to ''em all?'),(4,0,2,'Not likely.'),(4,2,0,'I wanna be the frst one to see ''em all.'),(4,0,2,'There we are. Good as new.'),(4,2,0,'What are you doing?'),(4,0,2,'Checking your blood for infections. Go on. You have a big day tomorrow. Sleep well, Ani.'),(4,0,3,'Obi-Wan?'),(4,3,0,'Yes, Master?'),(4,0,3,'I need an analysis of this blood sample I''m sending you.'),(4,3,0,'Wait a minute.'),(4,0,3,'I need a midi-chlorian count.'),(4,3,0,'The reading is off the chart. Over 20,000. Even Master Yoda doesn''t have a midi-chlorian count that high.'),(4,0,3,'No Jedi has.'),(4,3,0,'What does that mean?'),(4,0,3,'I''m not sure.'),(4,2,0,'What''d he mean by that?'),(4,0,2,'I''ll tell you later.'),(4,6,2,'Do what?'),(4,6,2,'You''ve never won a race?'),(4,2,6,'Well, not exactly.'),(4,6,2,'Not even finished?'),(4,2,6,'Kitster''s right. I will this time.'),(4,0,2,'Of course you will.'),(4,0,2,'You all set, Ani?'),(4,2,0,'Yep.'),(4,0,2,'Right. Remember, concentrate on the moment. Feel, don''t think. Use your instincts.'),(4,2,0,'I will.'),(4,0,2,'May the Force be with you.'),(4,6,0,'You Jedi are far too reckless. The queen is not...'),(4,0,6,'The queen trusts my judgment, young handmaiden. You should too.'),(4,6,0,'You assume too much.'),(4,2,2,'Oh, no! Nooo!'),(4,6,0,'Look. Here he comes.'),(4,6,2,'We owe you everything, Ani.'),(4,3,0,'Well, we have all the essential parts we need.'),(4,0,3,'I''m going back. Some unfinished business. I won''t be long.'),(4,3,0,'Why do I sense we''ve picked up another pathetic life-form?'),(4,0,3,'It''s the boy who''s responsible for getting us these parts. Get this hyperdrive generator installed.'),(4,3,0,'Yes, Master. That shouldn''t take long.'),(4,0,2,'Hey. These are yours.'),(4,2,2,'Yes!'),(4,0,2,'And he has been freed.'),(4,2,0,'What? '),(4,0,2,'You''re no longer a slave.'),(4,2,0,'You mean I get to come with you in your starship?'),(4,0,2,'Anakin... training to become a Jedi is not an easy challenge... and even if you succeed, it''s a hard life.'),(4,2,0,'But I wanna go. It''s what I''ve always dreamed of doing.'),(4,0,2,'Then pack your things. We haven''t much time.'),(4,2,2,'Yippee!'),(4,2,0,'What about Mom? Is she free too?'),(4,0,2,'I tried to free your mother, Ani, but Watto wouldn''t have it.'),(4,2,0,'Qui-Gon, sir, wait! I''m tired!'),(4,0,2,'Anakin! Drop! Go! Tell them to take off!'),(4,2,0,'Are you all right?'),(4,0,2,'I think so.'),(4,3,0,'What was it?'),(4,0,2,'I''m not sure... but it was well-trained in the Jedi arts.'),(4,0,3,'My guess is it was after the queen.'),(4,2,0,'What are we gonna do about it?'),(4,0,2,'We shall be patient.'),(4,0,2,'Anakin Skywalker... meet Obi-Wan Kenobi.'),(4,2,3,'Hi! You''re a Jedi too? Pleased to meet you.'),(4,6,2,'You all right?'),(4,2,6,'It''s very cold.'),(4,6,2,'You come from a warm planet, Ani. A little too warm for my taste. Space is cold.'),(4,2,6,'You seem sad.'),(4,6,2,'The queen is worried. Her people are suffering, dying. She must convince the senate to intervene or... I''m not sure what''ll happen.'),(4,2,6,'I made this for you... so you''d remember me. I carved it out of a japor snippet. It''ll bring you good fortune.'),(4,6,2,'It''s beautiful. But I don''t need this to remember you by. Many things will change when we reach the capital, Ani... but my caring for you will remain.'),(4,2,6,'I care for you, too, only l...'),(4,6,2,'Miss your mother.'),(4,6,2,'Ani, come on.'),(4,1,6,'There is no civility, only politics. The Republic is not what it once was. The senate is full of greedy, squabbling delegates. There is no interest in the common good. I must be frank, Your Majesty. There is little chance the senate will act on the invasion.'),(4,6,1,'Chancellor Valorum seems to think there is hope. If I may say so, Your Majesty... the chancellor has little real power. He is mired by baseless accusations of corruption. The bureaucrats are in charge now. What options have we?'),(4,1,6,'Our best choice would be to push for the election... of a stronger supreme chancellor... one who could control the bureaucrats... and give us justice. You could call for a vote of no confidence in Chancellor Valorum.'),(4,6,1,'He has been our strongest supporter.'),(4,1,6,'Our only other choice would be to submit a plea to the courts.'),(4,6,1,'The courts take even longer to decide things than the senate. Our people are dying, Senator. We must do something quickly to stop the Federation.'),(4,1,6,'To be realistic, Your Majesty... I think we''re going to have to accept Federation control... for the time being.'),(4,6,1,'That is something I cannot do.'),(4,0,7,'He was trained in the Jedi arts. My only conclusion can be that it was a Sith lord.'),(4,8,7,'I do not believe the Sith could have returned without us knowing.'),(4,7,8,'Hard to see, the dark side is.'),(4,8,0,'We will use all our resources to unravel this mystery. We will discover the identity of your attacker. May the Force be with you.'),(4,7,0,'Master Qui-Gon. More to say have you?'),(4,0,7,'With your permission, my master... I have encountered a vergence in the Force.'),(4,7,0,'A vergence, you say.'),(4,8,0,'Located around a person?'),(4,0,8,'A boy. His cells have the highest concentration of midi-chlorians... I have seen in a life-form. It is possible he was conceived by the midi-chlorians.'),(4,8,0,'You refer to the prophecy of the one who will bring balance to the Force. You believe it''s this boy?'),(4,0,8,'I don''t presume to...'),(4,7,0,'But you do. Revealed your opinion is.'),(4,0,7,'I request the boy be tested, Master.'),(4,7,0,'Oh? Trained as a Jedi you request for him, hmm?'),(4,0,7,'Finding him was the will of the Force. I have no doubt of that.'),(4,8,0,'Bring him before us, then.'),(4,6,2,'I''ve sent Padme on an errand.'),(4,2,6,'I''m on my way to the Jedi temple... to start my training, I hope. I may never see her again, so I came to say goodbye.'),(4,6,2,'We will tell her for you. We are sure her heart goes with you.'),(4,2,6,'Thank you, Your Highness.'),(4,1,6,'Enter the bureaucrat. The true rulers of the Republic. And on the payroll of the Trade Federation, I might add. This is where Chancellor Valorum''s strength will disappear.'),(4,1,6,'Now they will elect a new chancellor... a strong chancellor... one who will not let our tragedy continue.'),(4,3,0,'The boy will not pass the council''s test, Master. He''s too old.'),(4,0,3,'Anakin will become a Jedi, I promise you.'),(4,0,3,'I shall do what I must, Obi-Wan.'),(4,3,0,'If you would just follow the code, you would be on the council. They will not go along with you this time.'),(4,0,3,'You still have much to learn, my young apprentice.'),(4,2,8,'A ship. A cup. A ship. A speeder.'),(4,7,2,'How feel you?'),(4,2,7,'Cold, sir.'),(4,7,2,'Afraid are you?'),(4,2,7,'No, sir.'),(4,7,2,'See through you we can.'),(4,8,2,'Be mindful of your feelings.'),(4,7,2,'Afraid to lose her, I think, mmm?'),(4,2,7,'What has that got to do with anything?'),(4,7,2,'Everything. Fear is the path to the dark side. Fear leads to anger. Anger leads to hate. Hate leads to suffering. I sense much fear in you.'),(4,1,6,'A surprise, to be sure, but a welcome one. Your Majesty, if I am elected, I promise to put an end to corruption.'),(4,6,1,'Who else has been nominated?'),(4,1,6,'I feel confident our situation will create a strong sympathy vote for us. I will be chancellor.'),(4,6,1,'I fear by the time you have control of the bureaucrats, Senator... there''ll be nothing left of our people, our way of life.'),(4,1,6,'I understand your concern, Your Majesty. Unfortunately, the Federation has possession of our planet.'),(4,6,1,'Senator, this is your arena. I feel I must return to mine. I''ve decided to go back to Naboo.'),(4,1,6,'Go back? But, Your Majesty, be realistic. They''ll force you to sign the treaty.'),(4,6,1,'I will sign no treaty, Senator. My fate will be no different than that of our people.'),(4,1,6,'Please, Your Majesty. Stay here where it''s safe.'),(4,6,1,'It is clear to me now that the Republic no longer functions. I pray you will bring sanity and compassion back to the senate.'),(4,0,7,'He is to be trained, then?'),(4,8,0,'No, he will not be trained.'),(4,0,8,'No?'),(4,8,0,'He is too old.'),(4,0,7,'He is the chosen one. You must see it.'),(4,7,0,'Clouded this boy''s future is.'),(4,0,7,'I will train him, then. I take Anakin as my Padawan learner.'),(4,7,0,'An apprentice you have, Qui-Gon. Impossible to take on a second.'),(4,8,0,'The code forbids it.'),(4,0,7,'Obi-Wan is ready.'),(4,3,7,'I am ready to face the trials.'),(4,7,0,'Our own counsel we will keep on who is ready.'),(4,0,7,'He is headstrong and he has much to learn of the living Force... but he is capable. There is little more he can learn from me.'),(4,7,0,'Young Skywalker''s fate will be decided later.'),(4,8,0,'Now is not the time for this. The senate is voting for a new supreme chancellor... and Queen Amidala is returning home... which will put pressure on the Federation and could widen the confrontation.'),(4,8,0,'Go with the queen to Naboo and discover the identity of this dark warrior. This is the clue we need... to unravel the mystery of the Sith.'),(4,7,0,'May the Force be with you.'),(4,3,0,'It''s not disrespect, Master. It''s the truth.'),(4,0,3,'From your point of view.'),(4,3,0,'The boy is dangerous. They all sense it. Why can''t you?'),(4,0,3,'His fate is uncertain. He''s not dangerous. The council will decide Anakin''s future. That should be enough for you. Now get on board.'),(4,2,0,'Qui-Gon, sir, I don''t want to be a problem.'),(4,0,2,'You won''t be, Ani. I''m not allowed to train you... so I want you to watch me and be mindful. Always remember: Your focus determines your reality. Stay close to me and you''ll be safe.'),(4,2,0,'Master, sir... I heard Yoda talking about midi-chlorians. I''ve been wondering... What are midi-chlorians?'),(4,0,2,'Midi-chlorians are a microscopic life-form... that resides within all living cells.'),(4,2,0,'They live inside me?'),(4,0,2,'Inside your cells, yes. And we are symbionts with them.'),(4,2,0,'Symbionts?'),(4,0,2,'Life-forms living together for mutual advantage. Without the midi-chlorians, life could not exist... and we would have no knowledge of the Force. They continually speak to us... telling us the will of the Force. When you learn to quiet your mind... you''ll hear them speaking to you.'),(4,2,0,'I don''t understand.'),(4,0,2,'With time and training, Ani, you will. You will.'),(4,0,6,'Your Majesty, it is our pleasure to continue to serve and protect you.'),(4,6,0,'I welcome your help. Senator Palpatine fears that the Federation means to destroy me.'),(4,0,6,'I assure you I will not allow that to happen.'),(4,0,6,'I agree. I''m not sure what you wish to accomplish by this.'),(4,6,0,'I will take back what''s ours.'),(4,0,6,'And I can only protect you. I can''t fight a war for you.'),(4,3,0,'Jar Jar is on his way to the Gungan city, Master.'),(4,0,3,'Good.'),(4,3,0,'Do you think the queen''s idea will work?'),(4,0,3,'The Gungans will not be easily swayed. And we cannot use our power to help her.'),(4,3,0,'I''m sorry for my behaviour, Master. It''s not my place to disagree with you about the boy. And I am grateful you think I''m ready to take the trials.'),(4,0,3,'You''ve been a good apprentice, Obi-Wan. And you''re a much wiser man than I am. I foresee you will become a great Jedi knight.'),(4,3,0,'Do you think they have been taken to the camps?'),(4,1,5,'Lord Maul, be mindful. Let them make the first move.'),(4,5,1,'Yes, my master.'),(4,2,0,'They''re here!'),(4,6,0,'Good. They made it.'),(4,6,0,'The battle is a diversion. The Gungans must draw the droid army away from the cities.'),(4,6,0,'We can enter the city using the secret passages on the waterfall side. Once we get to the main entrance... Captain Panaka will create a diversion. Then we can enter the palace and capture the viceroy. Without the viceroy, they will be lost and confused.'),(4,6,0,'What do you think, Master Jedi?'),(4,0,6,'The viceroy will be well-guarded.'),(4,0,6,'There is a possibility, with this diversion, many Gungans will be killed.'),(4,0,6,'A well-conceived plan. However, there''s great risk. The weapons on your fghters may not penetrate the shields.'),(4,3,6,'And there''s an even bigger danger. If the viceroy escapes, Your Highness... he will return with another droid army.'),(4,6,3,'Well, that is why we must not fail to get the viceroy. Everything depends on it.'),(4,0,2,'Once we get inside, you find a safe place to hide and stay there.'),(4,2,0,'Sure.'),(4,0,2,'Stay there.'),(4,0,2,'Ani, find cover. Quick!'),(4,2,0,'Hey, wait for me!'),(4,0,2,'Anakin, stay where you are. You''ll be safe there.'),(4,2,0,' But l...'),(4,0,2,'Stay in that cockpit.'),(4,0,2,'We''ll handle this.'),(4,6,0,'We''ll take the long way.'),(4,0,3,'No, it''s too late.'),(4,3,0,'No.'),(4,0,3,'Obi-Wan. Promise... Promise me you will train the boy.'),(4,3,0,'Yes, Master. He is the chosen one. He will bring balance. Train him.'),(4,1,3,'We are indebted to you for your bravery, Obi-Wan Kenobi.'),(4,1,2,'And you, young Skywalker. We will watch your career with great interest.'),(4,6,1,'Congratulations on your election, Chancellor.'),(4,1,6,'Your boldness has saved our people, Your Majesty. It''s you who should be congratulated. Together we shall bring peace and prosperity to the Republic.'),(4,7,3,'Confer on you the level of Jedi knight the council does. But agree with your taking this boy as your Padawan learner... I do not.'),(4,3,7,'Qui-Gon believed in him.'),(4,7,3,'The chosen one the boy may be. Nevertheless... grave danger I fear in his training.'),(4,3,7,'Master Yoda, I gave Qui-Gon my word. I will train Anakin. Without the approval of the council, if I must.'),(4,7,3,'Qui-Gon''s defance I sense in you. Need that you do not. Agree with you the council does. Your apprentice Skywalker will be.'),(4,2,3,'What will happen to me now?'),(4,3,2,'The council have granted me permission to train you. You will be a Jedi, I promise.'),(4,8,7,'There''s no doubt the mysterious warrior was a Sith.'),(4,7,8,'Always two there are. No more, no less. A master and an apprentice.'),(4,8,7,'But which was destroyed? The master or the apprentice?'),(5,1,7,'I don''t know how much longer I can hold off the vote, my friends. More and more star systems are joining the separatists.'),(5,8,1,'If they do break away-'),(5,1,7,'I will not let this Republic... that has stood for a thousand years be split in two. My negotiations will not fail.'),(5,8,1,'If they do, you must realize there aren''t enough Jedi to protect the Republic. We''re keepers of the peace, not soldiers.'),(5,1,7,'Master Yoda. Do you think it will really come to war?'),(5,7,1,'The dark side clouds everything. Impossible to see the future is.'),(5,1,7,'We will discuss this matter later.'),(5,7,6,'Senator Amidala, Your tragedy on the landing platform, terrible. Seeing you alive brings warm feelings to my heart. brings warm feeling to my heart.'),(5,6,7,'Do you have any idea who was behind this attack?'),(5,8,6,'Our intelligence points to disgruntled spice miners, in the moons of Naboo.'),(5,6,8,'I think that Count Dooku was behind it.'),(5,8,6,'You know, M''Lady, Count Dooku was once a Jedi. He couldn''t assassinate anyone, it''s not in his character.'),(5,7,6,'But for certain Senator, in grave danger you are.'),(5,1,7,'Master Jedi, may I suggest that the Senator be placed under the protection of your graces.'),(5,6,1,'Chancellor, if I may comment, I do not believe that the...'),(5,1,6,'..."situation is that serious." No, but I do, Senator. I realize all too well that additional security might be disruptive for you, but perhaps someone you are familiar with... an old friend like... Master Kenobi...'),(5,8,1,'That''s possible. He''s just returned from a border dispute on Ansion.'),(5,1,6,'Do it for me, M''Lady... please, the thought of losing you is unbearable'),(5,8,6,'I''ll have Obi-Wan report to you immediately, M''Lady.'),(5,6,8,'Thank you Master Windu'),(5,3,2,'You seem a little on edge'),(5,2,3,'Not at all'),(5,3,2,'I haven''t felt you this tense since we fell into that nest of Gundarks'),(5,2,3,'You fell into that nightmare, master And I rescued you remember?'),(5,3,2,'Oh.. yes. You''re sweating, relax, take a deep breath.'),(5,2,3,'I haven''t seen her in ten years, Master.'),(5,3,6,'It''s a great pleasure to see you again, M''Lady.'),(5,6,3,'It has been far too long Master Kenobi.'),(5,6,2,'Ani?? My goodness you''ve grown.'),(5,2,6,'So have you... grown more beautiful, I mean... well... for a Senator, I mean.'),(5,6,2,'Ani, you''ll always be that little boy I knew on Tatooine.'),(5,3,6,'Our presence will be invisible, M''Lady. I can assure you'),(5,6,2,'I don''t need more security, I need answers. I want to know who is trying to kill me.'),(5,3,6,'We''re here to protect you Senator, not to start an investigation.'),(5,2,6,'We will find out who is trying to kill you Padme, I promise you.'),(5,3,2,'We will not exceed our mandate, my young Padawan learner.'),(5,2,3,'I meant that in the interest of protecting her, Master, of course.'),(5,3,2,'We will not going through this exercise again, Anakin. And you will pay attention to my lead.'),(5,2,3,'Why?'),(5,3,2,'What??!!'),(5,2,3,'Why else do you think we were assigned to her, if not to find the killer? Protection is a job for local security... not Jedi. It''s overkill, Master. Investigation is implied in our mandate.'),(5,3,2,'We will do exactly as the Council has instructed, and you will learn your place, young one.'),(5,6,2,'Perhaps with merely your presence, the mysteries surrounding this threat will be revealed. Now if you will excuse me I will retire.'),(5,3,2,'You''re focusing on the negative, Anakin. Be mindful of your thoughts. She was pleased to see us. Now lets check the security.'),(5,3,2,'Captain Typho has more than enough men downstairs. No assassin will try that way. Any activity up here?'),(5,2,3,'Quiet as a tomb. I don''t like just waiting here for something to happen to her.'),(5,3,2,'What''s going on?'),(5,2,3,'She covered the cameras. I don''t think she liked me watching her.'),(5,3,2,'What is she thinking?'),(5,2,3,'She programmed Artoo to warn us if there''s an intruder.'),(5,3,2,'There are many other ways to kill a Senator.'),(5,2,3,'I know, but we also want to catch this assassin. Don''t we, Master?'),(5,3,2,'You''re using her as bait?'),(5,2,3,'It was her idea... Don''t worry, no harm will come to her. I can sense everything going on in that room. Trust me.'),(5,3,2,'It''s too risky... besides, your senses aren''t that attuned, my young apprentice.'),(5,2,3,'And yours are?'),(5,3,2,'Possibly. You look tired.'),(5,2,3,'I don''t sleep well, anymore.'),(5,3,2,'Because of your mother?'),(5,2,3,'I don''t know why I keep dreaming bbout her.'),(5,3,2,'Dreams pass in time.'),(5,2,3,'I''d much rather dream about Padme. Just being around her again is... intoxicating.'),(5,3,2,'Be mindful of your thoughts, Anakin, they betray you. You''ve made a commitment to the Jedi order... a commitment not easily broken... and don''t forget she''s a politician and they''re not to be trusted.'),(5,2,3,'She''s not like the others in the Senate, Master.'),(5,3,2,'It''s been my experience that Senators are only focused on pleasing those who fund their campaigns... and they are in no means scared of forgetting the niceties of democracy in order to get those funds.'),(5,2,3,'Not another lecture, Master. At least not on the economics of politics....'),(5,2,3,'And besides, you''re generalizing. The Chancellor doesn''t appear to be corrupt.'),(5,3,2,'Palpatine is a politician, I have observed that he is very clever at following the passions and prejudices of the Senators.'),(5,2,3,'I think he''s a good man. My-'),(5,3,2,'I sense it, too.'),(5,2,6,'Stay here!'),(5,3,2,'What took you so long?'),(5,2,3,'Oh, you know, Master, I couldn''t find a speeder that I really liked,'),(5,3,2,'There he is'),(5,2,3,'with an open cockpit... and with the right speed capabilities...'),(5,3,2,'If you spent as much time practicing your saber techniques as you do on your wit you would rival Master Yoda as a swordsman.'),(5,2,3,'I thought I already did.'),(5,3,2,'Only in your mind, my very young apprentice. Pull up, Anakin. Pull up! You know I don''t like it when you do that.'),(5,2,3,'Sorry, Master, I forgot you don''t like flying.'),(5,3,2,'I don''t mind flying... but what you''re doing is suicide! Anakin! How many times have I told you stay away from power couplings! That was good. Where are you going?! He went that way.'),(5,2,3,'Master, if we keep this chase going, that creep''s gonna end up deep fried. Personally, I''d very much like to find out who he is and who he''s working for... This is a shortcut. I think.'),(5,3,2,'Well, you''ve lost him.'),(5,2,3,'I''m deeply sorry, Master.'),(5,3,2,'That was some shortcut, Anakin. He went completely the other way. Once again you''ve proved...'),(5,2,3,'If you''ll excuse me.'),(5,3,3,'I hate it when he does that.'),(5,3,2,'Anakin!'),(5,2,3,'She went into the club, Master.'),(5,3,2,'Patience. Use the Force. Think.'),(5,2,3,'Sorry, Master.'),(5,3,2,'He went in there to hide, not to run.'),(5,2,3,'Yes, Master.'),(5,3,2,'Next time, try not to lose it.'),(5,2,3,'Yes, Master.'),(5,3,2,'This weapon is your life.'),(5,2,3,'I try, Master.'),(5,3,2,'Why do I get the feeling you''re going to be the death of me?!'),(5,2,3,'Don''t say that Master... You''re the closest thing I have to a father...'),(5,3,2,'Then why don''t you listen to me?!'),(5,2,3,'I am trying'),(5,3,2,'Can you see him?'),(5,2,3,'I think he is a she... And I think she is a changeling'),(5,3,2,'In that case, extra careful... Go and find her.'),(5,2,3,'Where are you going, Master?'),(5,3,2,'For a drink.'),(5,3,2,'Toxic dart...'),(5,7,3,'Track down this bounty hunter you must, Obi-Wan.'),(5,8,3,'Most importantly, find out who he''s working for.'),(5,3,7,'What about Senator Amidala? She will still need protecting.'),(5,7,3,'Handle that your Padawan will.'),(5,8,2,'Anakin, escort the senator back to her home planet of Naboo. She''ll be safer there. And don''t use registered transport. Travel as refugees.'),(5,2,8,'As the leader of the opposition, it will be very difficult... to get Senator Amidala to leave the capital.'),(5,7,2,'Until caught this killer is... our judgment she must respect.'),(5,8,2,'Anakin, go to the senate... and ask Chancellor Palpatine to speak with her about this matter.'),(5,1,2,'I will talk with her. Senator Amidala will not refuse an executive order. I know her well enough to assure you of that.'),(5,2,1,'Thank you, Your Excellency.'),(5,1,2,'And so, they''ve finally given you an assignment. Your patience has paid off'),(5,2,1,'Your guidance more than my patience.'),(5,1,2,'You don''t need guidance, Anakin. In time, you will learn to trust your feelings. Then you will be invincible. I have said it many times: You are the most gifted Jedi I have ever met.'),(5,2,1,'Thank you, Your Excellency.'),(5,1,2,'I see you becoming the greatest of all the Jedi, Anakin.. even more powerful than Master Yoda.'),(5,3,7,'I am concerned for my Padawan. He is not ready to be given this assignment on his own yet.'),(5,7,3,'The Council is confident in its decision, Obi-Wan.'),(5,8,3,'The boy has exceptional skills.'),(5,3,7,'But he still has much to learn, Master. And his abilities have made him... well... arrogant.'),(5,7,3,'Yes, yes. A flaw more and more common among Jedi. Too sure of themselves they are. Even the older, more experienced ones.'),(5,8,3,'Remember, Obi-Wan, if the prophecy is true... your apprentice is the only one who can bring the Force back into balance.'),(5,6,2,'I do not like this idea of hiding.'),(5,2,6,'Don''t worry. Now that the Council has ordered an investigation, it won''t take Master Obi-Wan long to find this bounty hunter.'),(5,6,2,'I haven''t worked for a year to defeat the Military Creation Act... to not be here when its fate is decided.'),(5,2,6,'Sometimes we must let go of our pride and do what is requested of us.'),(5,6,2,'Anakin, you''ve grown up.'),(5,2,6,'Master Obi-Wan manages not to see it. Don''t get me wrong. Obi-Wan is a great mentor. As wise as Master Yoda and... as powerful as Master Windu. I am truly thankful to be his apprentice. In some ways-- a lot of ways-- I''m really ahead of him. I''m ready for the trials... but he feels that I''m too unpredictable. He won''t let me move on.'),(5,6,2,'That must be frustrating.'),(5,2,6,'It''s worse. He''s overly critical. He never listens. He doesn''t understand. It''s not fair!'),(5,6,2,'All mentors have a way of seeing more of our faults than we would like. It''s the only way we grow.'),(5,2,6,'I know.'),(5,6,2,'Anakin.'),(5,6,2,'Don''t try to grow up too fast.'),(5,2,2,'But I am grown up. You said it yourself.'),(5,6,2,'Please don''t look at me like that.'),(5,2,6,'Why not?'),(5,6,2,'It makes me feel uncomfortable.'),(5,2,6,'Sorry, milady.'),(5,3,2,'Anakin. Don''t do anything without first consulting either myself or the council.'),(5,2,3,'Yes, Master.'),(5,3,6,'I''ll get to the bottom of this plot quickly, milady. You''ll be back here in no time.'),(5,6,3,'I''ll be most grateful for your speed, Master Jedi.'),(5,2,6,'It''s time to go.'),(5,6,2,'I know.'),(5,3,2,'Anakin, may the Force be with you.'),(5,2,3,'May the Force be with you, Master.'),(5,6,2,'Suddenly I''m afraid.'),(5,2,6,'This is my first assignment on my own. I am too. Don''t worry. We have Artoo with us.'),(5,6,2,'Must be difficult, having sworn your life to the Jedi... not being able to visit the places you like or do the things you like.'),(5,2,6,'Or be with the people that I love.'),(5,6,2,'Are you allowed to love? I thought that was forbidden for a Jedi.'),(5,2,6,'Attachment is forbidden. Possession is forbidden. Compassion, which I would define as unconditional love... is central to a Jedi''s life. So you might say that we are encouraged to love.'),(5,6,2,'You''ve changed so much.'),(5,2,6,'You haven''t changed a bit.'),(5,2,2,'You''re exactly the way I remember you in my dreams.'),(5,3,7,'I''m sorry to disturb you, Master.'),(5,7,3,'What help can I be, Obi-Wan?'),(5,3,7,'I''m looking for a planet described to me by an old friend. I trust him, but the systems don''t show on the archive maps.'),(5,7,3,'Lost a planet Master Obi-Wan has. How embarrassing. How embarrassing. Liam, the shades. Gather round the map reader. Clear your minds... and find Obi-Wan''s wayward planet we will.'),(5,3,7,'It ought to be... here... but it isn''t. Gravity is pulling all the stars in the area towards this spot.'),(5,7,3,'Hmm. Gravity''s silhouette remains... but the star and all the planets... disappeared they have. How can this be? Hmm? A thought? Anyone.'),(5,7,3,'Truly wonderful the mind of a child is. The Padawan is right. Go to the center of gravity''s pull... and find your planet you will. The data must have been erased.'),(5,3,7,'But, Master Yoda, who could empty information from the archives? That''s impossible, isn''t it?'),(5,7,3,'Dangerous and disturbing this puzzle is. Only a Jedi could have erased those files. But who and why, harder to answer. Meditate on this I will.'),(5,6,2,'I wasn''t the youngest queen ever elected... but now that I think back on it, I''m not sure I was old enough. I''m not sure I was ready.'),(5,2,6,'The people you served thought you did a good job. I heard they even tried to amend the constitution so you could stay in office.'),(5,6,2,'I was relieved when my two terms were up. But when the queen asked me to serve as senator... I couldn''t refuse her.'),(5,2,6,'I agree with her. I think the Republic needs you. I''m glad that you chose to serve.'),(5,2,6,'Hold on a minute.'),(5,6,2,'Excuse me.'),(5,2,6,'Excuse me. I''m in charge of security here, milady.'),(5,6,2,'And this is my home. I know it very well. That is why we''re here. I think it would be wise if you took advantage of my knowledge in this instance.'),(5,2,6,'Sorry, milady.'),(5,6,2,'We used to come here for school retreat. We would swim to that island every day. I love the water. We used to lie out on the sand and let the sun dry us... and try to guess the names of the birds singing.'),(5,2,6,'I don''t like sand. It''s coarse and rough and irritating... and it gets everywhere. Not like here. Here, everything is soft... and smooth.'),(5,6,2,'No. I shouldn''t have done that.'),(5,2,6,'I''m sorry.'),(5,6,2,'I don''t know.'),(5,2,6,'Sure you do. You just don''t want to tell me.'),(5,6,2,'You gonna use one of your Jedi mind tricks on me?'),(5,2,6,'They only work on the weak-minded.'),(5,6,2,'All right. I was twelve. His name was Palo. We were both in the Legislative Youth Program. He was a few years older than I. Very cute. Dark, curly hair. Dreamy eyes.'),(5,2,6,'All right, I get the picture. Whatever happened to him?'),(5,6,2,'I went into public service; he went on to become an artist.'),(5,2,6,'Maybe he was the smart one.'),(5,6,2,'You really don''t like politicians, do you?'),(5,2,6,'I like two or three... but I''m not really sure about one of them. I don''t think the system works.'),(5,6,2,'How would you have it work?'),(5,2,6,'We need a system where the politicians sit down and discuss the problem... agree what''s in the best interest of all the people, and then do it.'),(5,6,2,'That''s exactly what we do. The trouble is that people don''t always agree.'),(5,2,6,'Well, then they should be made to.'),(5,6,2,'By whom? Who''s gonna make them?'),(5,2,6,'I don''t know. Someone.'),(5,6,2,'You?'),(5,2,6,'Of course not me.'),(5,6,2,'But someone.'),(5,2,6,'Someone wise.'),(5,6,2,'Sounds an awful lot like a dictatorship to me.'),(5,2,6,'Well, if it works.'),(5,6,2,'You''re making fun of me.'),(5,2,6,'No. I''d be much too frightened to tease a senator.'),(5,6,2,'Ani! Ani, are you all right?'),(5,2,6,'And when I got to them, we went into aggressive negotiations.'),(5,6,2,'Aggressive negotiations? What''s that?'),(5,2,6,'Uh, well, negotiations with a lightsaber.'),(5,6,2,'Oh.')
GO

INSERT INTO Dialogue (Movie, FromID, ToID, Dialogue)
VALUES
(5,2,6,'If Master Obi-Wan caught me doing this, he''d be very grumpy. From the moment I met you... all those years ago... not a day has gone by when I haven''t thought of you. And now that I''m with you again... I''m in agony. The closer I get to you, the worse it gets. The thought of not being with you-- I can''t breathe. I''m haunted by the kiss that you should never have given me. My heart is beating... hoping that that kiss will not become a scar. You are in my very soul... tormenting me. What can I do? I will do anything that you ask. If you are suffering as much as I am, please, tell me.'),(5,6,2,'I can''t. We can''t. It''s...just not possible.'),(5,2,6,'Anything is possible, Padme. Listen to me.'),(5,6,2,'No, you listen. We live in a real world. Come back to it. You''re studying to become a Jedi. I''m- I''m a senator. If you follow your thoughts through to conclusion... it''ll take us to a place we cannot go... regardless of the way we feel about each other.'),(5,2,6,'Then you do feel something.'),(5,6,2,'I will not let you give up your future for me.'),(5,2,6,'You are asking me to be rational. That is something I know I cannot do. Believe me, I wish that I could just wish away my feelings... but I can''t.'),(5,6,2,'I will not give in to this.'),(5,2,6,'Well, you know, it... wouldn''t have to be that way. We could keep it a secret.'),(5,6,2,'We''d be living a lie... one we couldn''t keep even if we wanted to. I couldn''t do that. Could you, Anakin? Could you live like that?'),(5,2,6,'No. You''re right. It would destroy us.'),(5,3,7,'I have successfully made contact with the prime minister of Kamino. They are using a bounty hunter named Jango Fett to create a clone army. I have a strong feeling that this bounty hunter... is the assassin we are looking for.'),(5,8,3,'Do you think these cloners are involved in the plot to assassinate Senator Amidala?'),(5,3,8,'No, Master. There appears to be no motive.'),(5,7,3,'Do not assume anything, Obi-Wan. Clear your mind must be... if you are to discover the real villains behind this plot.'),(5,3,7,'Yes, Master.'),(5,3,7,'They say Master Sifo-Dyas placed an order for a clone army... at the request of the senate almost ten years ago. I was under the impression he was killed before that. Did the council ever authorize the creation of a clone army?'),(5,8,3,'No. Whoever placed that order did not have the authorization of the Jedi Council.'),(5,7,3,'Bring him here. Question him we will.'),(5,3,7,'Yes, Master. I will report back when I have him.'),(5,7,8,'Blind we are if creation of this clone army... we could not see.'),(5,8,7,'I think it is time we informed the senate... that our ability to use the Force has diminished.'),(5,7,8,'Only the dark lord of the Sith knows of our weakness. If informed the senate is... multiply our adversaries will.'),(5,2,2,'No. No.'),(5,2,6,'Don''t go.'),(5,6,2,'I don''t want to disturb you.'),(5,2,6,'Your presence is soothing.'),(5,6,2,'You had another nightmare last night.'),(5,2,6,'Jedi don''t have nightmares.'),(5,6,2,'I heard you.'),(5,2,6,'I saw my mother. She is suffering, Padme. I saw her as clearly as I see you now. She is in pain. I know I''m disobeying my mandate to protect you, Senator... but I have to go. I have to help her.'),(5,6,2,'I''ll go with you.'),(5,2,6,'I''m sorry. I don''t have a choice.'),(5,3,3,'Oh, not good.'),(5,3,3,'Oh, blast! This is why I hate flying!'),(5,2,6,'You''re gonna have to stay here. These are good people, Padme. You''ll be safe.'),(5,6,2,'Anakin--'),(5,2,6,'I won''t be long.'),(5,8,7,'What is it?'),(5,7,8,'Pain, suffering... death I feel. Something terrible has happened. Young Skywalker is in pain. Terrible pain.'),(5,3,3,'The transmitter is working, but we''re not receiving a return signal. Coruscant''s too far.'),(5,6,2,'I brought you something. Are you hungry?'),(5,2,6,'The shifter broke. Life seems so much simpler when you''re fixing things. I''m good at fixing things. Always was. But I couldn''t-- Why''d she have to die? Why couldn''t I save her? I know I could have!'),(5,6,2,'Sometimes there are things no one can fix. You''re not all-powerful, Ani.'),(5,2,6,'Well, I should be! Someday I will be. I will be the most powerful Jedi ever! I promise you. I will even learn to stop people from dying.'),(5,6,2,'Anakin.'),(5,2,6,'It''s all Obi-Wan''s fault! He''s jealous! He''s holding me back!'),(5,6,2,'What''s wrong, Ani?'),(5,2,6,'I-- I killed them. I killed them all. They''re dead. Every single one of them. And not just the men... but the women... and the children too. They''re like animals, and I slaughtered them like animals! I hate them!'),(5,6,2,'To be angry is to be human.'),(5,2,6,'I''m a Jedi. I know I''m better than this.'),(5,3,1,'Anakin, my long-range transmitter has been knocked out. Retransmit this message to Coruscant. I have tracked the bounty hunter, Jango Fett... to the droid foundries on Geonosis. The Trade Federation is to take delivery of a droid army here... and it is clear that Viceroy Gunray... is behind the assassination attempts on Senator Amidala. The Commerce Guilds and the Corporate Alliance... have both pledged their armies to Count Dooku and are forming a-- Wait. Wait.'),(5,7,8,'More happening on Geonosis, I feel, than has been revealed.'),(5,8,7,'I agree.'),(5,8,2,'Anakin, we will deal with Count Dooku. The most important thing for you is to stay where you are. Protect the senator at all costs. That is your first priority.'),(5,2,8,'Understood, Master.'),(5,6,2,'They''ll never get there in time to save him. They have to come halfway across the galaxy. Look. Geonosis is less than a parsec away.'),(5,2,6,'If he''s still alive.'),(5,6,2,'Ani, are you just gonna sit here and let him die? He''s your friend, your mentor. He''s--'),(5,2,6,'He''s like my father! But you heard Master Windu. He gave me strict orders to stay here!'),(5,6,2,'He gave you strict orders to protect me... and I''m going to help Obi-Wan. If you plan to protect me, you''ll just have to come along.'),(5,1,7,'Count Dooku must have made a treaty with them.'),(5,1,7,'But what senator would have the courage to propose such a radical amendment?'),(5,3,4,'Traitor.'),(5,4,3,'Oh, no, my friend. This is a mistake, a terrible mistake. They have gone too far. This is madness.'),(5,3,4,'I thought you were the leader here, Dooku.'),(5,4,3,'This had nothing to do with me, I assure you. I will petition immediately to have you set free.'),(5,3,4,'Well, I hope it doesn''t take too long. I have work to do.'),(5,4,3,'May I ask why a Jedi knight... is all the way out here on Geonosis?'),(5,3,4,'I''ve been tracking a bounty hunter named Jango Fett. Do you know him?'),(5,4,3,'There are no bounty hunters here that I am aware of. The Geonosians don''t trust them.'),(5,3,4,'Who can blame them? But he is here, I can assure you.'),(5,4,3,'It''s a great pity that our paths have never crossed before, Obi-Wan. Qui-Gon always spoke very highly of you. I wish he were still alive. I could use his help right now.'),(5,3,4,'Qui-Gon Jinn would never join you.'),(5,4,3,'Don''t be so sure, my young Jedi. You forget that he was once my apprentice... just as you were once his. He knew all about the corruption in the senate... but he would never have gone along with it if he had learned the truth as I have.'),(5,3,4,'The truth?'),(5,4,3,'The truth. What if I told you that the Republic... was now under the control of the dark lord of the Sith?'),(5,3,4,'No, that''s not possible. The Jedi would be aware of it.'),(5,4,3,'The dark side of the Force has clouded their vision, my friend. Hundreds of senators are now under the influence... of a Sith lord called Darth Sidious.'),(5,3,4,'I don''t believe you.'),(5,4,3,'The viceroy of the Trade Federation... was once in league with this Darth Sidious... but he was betrayed ten years ago by the dark lord. He came to me for help. He told me everything. You must join me, Obi-Wan... and together we will destroy the Sith!'),(5,3,4,'I will never join you, Dooku.'),(5,4,3,'It may be difficult to secure your release.'),(5,8,7,'It is done, then. I will take what Jedi we have left and go to Geonosis and help Obi-Wan.'),(5,7,8,'Visit I will the cloners on Kamino... and see this army they have created for the Republic.'),(5,6,2,'See those columns of steam straight ahead? They''re exhaust vents of some type.'),(5,2,6,'That''ll do.'),(5,6,2,'Look, whatever happens out there, follow my lead. I''m not interested in getting into a war here. As a member of the senate... maybe I can find a diplomatic solution to this mess.'),(5,2,6,'Don''t worry. I''ve given up trying to argue with you.'),(5,2,6,'Wait.'),(5,2,6,'Padme!'),(5,2,2,'Oh, not again. Obi-Wan''s gonna kill me.'),(5,2,6,'Don''t be afraid.'),(5,6,2,'I''m not afraid to die. I''ve been dying a little bit each day since you came back into my life.'),(5,2,6,'What are you talking about?'),(5,6,2,'I love you.'),(5,2,6,'You love me? I thought that we had decided not to fall in love... that we would be forced to live a lie... and that it would destroy our lives.'),(5,6,2,'I think our lives are about to be destroyed anyway. I truly... deeply love you... and before we die, I want you to know.'),(5,3,2,'I was beginning to wonder if you''d got my message.'),(5,2,3,'I retransmitted it just as you had requested, Master. Then we decided to come and rescue you.'),(5,3,2,'Good job.'),(5,2,3,'I''ve got a bad feeling about this.'),(5,3,2,'Just relax. Concentrate.'),(5,2,3,'What about Padme?'),(5,3,2,'She seems to be on top of things.'),(5,2,6,'Jump!'),(5,4,8,'Master Windu, how pleasant of you to join us.'),(5,8,4,'This party''s over.'),(5,4,8,'Brave but foolish, my old Jedi friend. You''re impossibly outnumbered.'),(5,8,4,'I don''t think so.'),(5,4,8,'We''ll see.'),(5,2,6,'You call this a diplomatic solution?'),(5,6,2,'No, I call it aggressive negotiations.'),(5,4,8,'Master Windu, you have fought gallantly... worthy of recognition in the archives of the Jedi order. Now it is finished. Surrender, and your lives will be spared.'),(5,8,4,'We will not be hostages to be bartered, Dooku!'),(5,4,8,'Then, I''m sorry, old friend.'),(5,3,2,'Hold on!'),(5,3,2,'Good call, my young Padawan.'),(5,3,2,'Look over there!'),(5,2,3,'It''s Dooku!'),(5,6,2,'We''re gonna need some help!'),(5,3,2,'There isn''t time! Anakin and I can handle this!'),(5,2,6,'Padme!'),(5,3,2,'Anakin! Don''t let your personal feelings get in the way! Follow that speeder!'),(5,3,2,'I can''t take Dooku alone! I need you! If we catch him, we can end this war right now! We have a job to do!'),(5,2,3,'I don''t care! '),(5,3,2,'You will be expelled from the Jedi order!'),(5,2,3,'I can''t leave her!'),(5,3,2,'Come to your senses! What do you think Padme would do were she in your position?'),(5,2,3,'She would do her duty.'),(5,2,4,'You''re gonna pay for all the Jedi that you killed today, Dooku.'),(5,3,2,'We''ll take him together. Go in slowly on the left.'),(5,2,3,'I''m taking him now!'),(5,3,2,'No, Anakin! No! No!'),(5,4,3,'As you see, my Jedi powers are far beyond yours. Now... back down.'),(5,3,4,'I don''t think so.'),(5,4,3,'Master Kenobi, you disappoint me. Yoda holds you in such high esteem. Surely you can do better.'),(5,4,2,'Brave of you, boy. But I would have thought you had learned your lesson.'),(5,2,4,'I am a slow learner.'),(5,3,2,'Anakin!'),(5,4,7,'Master Yoda.'),(5,7,4,'Count Dooku.'),(5,4,7,'You have interfered with our affairs for the last time.'),(5,7,4,'Powerful you have become, Dooku. The dark side I sense in you.'),(5,4,7,'I''ve become more powerful than any Jedi. Even you.'),(5,7,4,'Much to learn you still have.'),(5,4,7,'It is obvious that this contest cannot be decided by our knowledge of the Force... but by our skills with a lightsaber.'),(5,7,4,'Fought well you have, my old Padawan.'),(5,4,7,'This is just the beginning.'),(5,6,2,'Anakin!'),(5,4,1,'The Force is with us, Master Sidious.'),(5,1,4,'Welcome home, Lord Tyranus. You have done well.'),(5,4,1,'I have good news for you, my lord. The war has begun.'),(5,1,4,'Excellent. Everything is going as planned.'),(5,3,7,'Do you believe what Count Dooku said... about Sidious controlling the senate? It doesn''t feel right.'),(5,7,3,'Joined the dark side Dooku has. Lies, deceit... creating mistrust are his ways now.'),(5,8,3,'Nevertheless, I feel we should keep a closer eye on the senate.'),(5,7,3,'I agree.'),(5,8,3,'Where is your apprentice?'),(5,3,8,'On his way to Naboo, escorting Senator Amidala home.'),(5,3,7,'I have to admit that without the clones, it would not have been a victory.'),(5,7,3,'Victory? Victory, you say? Master Obi-Wan, not victory. The shroud of the dark side has fallen. Begun the Clone War has.'),(6,2,3,'Master, General Grievous''s ship is directly ahead. The one crawling with vulture droids.'),(6,3,2,'I see it. Oh, this is going to be easy.'),(6,2,3,'This is where the fun begins.'),(6,2,3,'I''m gonna go help them out.'),(6,3,2,'No. No. They are doing their job so we can do ours'),(6,2,3,'Missiles. Pull up.'),(6,3,2,'They overshot us.'),(6,2,3,'They''re coming around.'),(6,3,3,'Flying is for droids.'),(6,3,2,'I''m hit. Anakin?'),(6,2,3,'I see them. Buzz droids.'),(6,3,3,'Oh, dear.'),(6,3,2,'They''re shutting down all the controls.'),(6,2,3,'Move to the right so I can get a clear shot at them.'),(6,3,2,'The mission. Get to the command ship. Get the chancellor. I''m running out of tricks here. In the name of- Hold your fire! You''re not helping.'),(6,2,3,'I agree. Bad idea.'),(6,3,2,'I can''t see a thing. My cockpit''s fogging. They''re all over me. Anakin!'),(6,2,3,'Move to the right.'),(6,3,2,'Hold on, Anakin. You''re gonna get us both killed. Get out of here. There''s nothing more you can do.'),(6,2,3,'I''m not leaving without you, Master.'),(6,2,3,'The General''s Command Ship is dead ahead.'),(6,3,2,'Well, have you noticed the shields are still up?'),(6,2,3,'Sorry, Master.'),(6,3,2,'Oh, I have a bad feeling about this.'),(6,3,2,'The Chancellor''s signal is coming from right there. The observation platform at the top of that spire.'),(6,2,3,'I sense Count Dooku...'),(6,3,2,'I sense a trap.'),(6,2,3,'Next move?'),(6,3,2,'Spring the trap.'),(6,2,3,'Destroyers!!'),(6,3,2,'Did you press the stop button?'),(6,2,3,'No, did you?'),(6,3,2,'No!'),(6,2,3,'Well, there''s more than one way out of here.'),(6,3,2,'We don''t want to get out, we want to get moving.'),(6,3,3,'Always on the move.'),(6,3,2,'Oh, it''s you...'),(6,2,3,'What was that all about?'),(6,3,2,'Well, Artoo has been...'),(6,2,3,'No loose wire jokes...'),(6,3,2,'Did I say anything?'),(6,2,3,'He''s trying!'),(6,3,2,'I didn''t say anything!'),(6,3,1,'Chancellor.'),(6,2,1,'Are you all right?'),(6,1,2,'Count Dooku.'),(6,3,2,'This time we will do it together.'),(6,2,3,'I was about to say that.'),(6,1,2,'Get help! You''re no match for him. He''s a Sith Lord.'),(6,3,1,'Chancellor Palpatine, Sith Lords are our specialty.'),(6,4,2,'Your swords, please. We don''t want to make a mess of things in front of the Chancellor.'),(6,3,4,'You won''t get away this time, Dooku.'),(6,4,2,'I''ve been looking forward to this.'),(6,2,4,'My powers have doubled since the last time we met, Count.'),(6,4,2,'Good. Twice the pride, double the fall.'),(6,4,2,'I sense great fear in you, Skywalker. You have hate, you have anger, but you don''t use them.'),(6,1,2,'Good, Anakin, good.Kill him. Kill him now!'),(6,2,1,'I shouldn''t...'),(6,1,2,'Do it!! You did well, Anakin. He was too dangerous to be kept alive.'),(6,2,1,'Yes, but he was an unarmed prisoner. I shouldn''t have done that, Chancellor. It''s not the Jedi way.'),(6,1,2,'It is only natural. He cut off your arm, and you wanted revenge. It wasn''t the first time, Anakin. Remember what you told me about your mother and the Sand People. Now, we must leave before more security droids arrive. Anakin, there is no time. We must get off the ship before it''s too late.'),(6,2,1,'He seems to be all right.'),(6,1,2,'Leave him, or we''ll never make it.'),(6,2,1,'His fate will be the same as ours.'),(6,2,1,'Elevator''s not working,'),(6,2,3,'Easy... We''re in a bit of a situation.'),(6,3,2,'Did I miss something?'),(6,2,3,'Hold on.'),(6,3,2,'What is that?'),(6,2,3,'Uh, oops.'),(6,3,2,'Too late! Jump! Let''s see if we can find something in the hangar bay that''s still flyable. Come on.'),(6,2,3,'Ray shields!'),(6,3,2,'Wait a minute, how''d this happen! We''re smarter than this.'),(6,2,3,'Apparently not. I say patience.'),(6,3,2,'Patience?'),(6,2,3,'Yes, Artoo will be along in a few moments and then he''ll release the ray shields...'),(6,2,3,'See! No problem.'),(6,3,2,'Do you have a plan B?'),(6,9,3,'Ah yes. The Negotiator, General Kenobi. We''ve been waiting for you. That wasn''t much of a rescue.'),(6,9,2,'And Anakin Skywalker... I was expecting someone with your reputation to be a little older.'),(6,2,9,'General Grievous... You''re shorter than I expected.'),(6,9,2,'Jedi scum...'),(6,3,2,'We have a job to do. Anakin, try not to upset him.'),(6,9,2,'Your lightsabers will make a fine addition to my collection.'),(6,3,9,'Not this time. And this time you won''t escape.'),(6,9,3,'You lose, General Kenobi.'),(6,9,9,'Time to abandon ship.'),(6,2,3,'All the escape pods have been launched.'),(6,3,2,'Grievous. Can you fly a cruiser like this?'),(6,2,3,'You mean, do I know how to land what''s left of this thing?'),(6,3,2,'Well?'),(6,2,3,'Under the circumstances, I''d say the ability to pilot this thing is irrelevant. Strap yourselves in. Open all hatches, extend all flaps, and drag fins.'),(6,2,3,'We lost something.'),(6,3,2,'Not to worry, we''re still flying half a ship.'),(6,2,3,'Now we''re really picking up speed...'),(6,3,2,'Eight plus sixty. We''re in the atmosphere...'),(6,2,3,'Grab that... Keep us level.'),(6,3,2,'Steady.'),(6,3,2,'Five thousand. Fire ships on the left and the right.'),(6,3,2,'Landing strip''s straight ahead.'),(6,2,3,'We''re coming in too hot.'),(6,3,2,'Another happy landing.'),(6,2,3,'Are you coming, Master?'),(6,3,2,'Oh no. I''m not brave enough for politics. I have to report to the Council. Besides, someone needs to be the poster boy.'),(6,2,3,'Hold on, this whole operation was your idea.'),(6,3,2,'Let us not forget, Anakin, that you rescued me from the Buzz Droids. And you killed Count Dooku. And you rescued the Chancellor, carrying me unconscious on your back.'),(6,2,3,'All because of your training.'),(6,3,2,'Anakin, let''s be fair. Today, you were the hero and you deserve your glorious day with the politicians.'),(6,2,3,'All right. But you owe me one... and not for saving your skin for the tenth time...'),(6,3,2,'Ninth time... that business on Cato Nemoidia doesn''t- doesn''t count. I''ll see you at the briefing.'),(6,8,1,'Chancellor Palpatine, are you all right?'),(6,1,8,'Yes, thanks to your two Jedi Knights. They killed Count Dooku, but General Grievous has escaped once again.'),(6,8,1,'General Grievous will run and hide, as he always does. He''s a coward.'),(6,1,8,'But with Count Dooku dead, he is the leader of the Droid Army, and I assure you, the Senate will vote to continue the war as long as Grievous is alive.'),(6,8,1,'Then the Jedi Council will make finding Grievous our highest priority.'),(6,6,2,'Oh, Anakin!'),(6,2,6,'I''ve missed you, Padme.'),(6,6,2,'There were whispers... that you''d been killed.'),(6,2,6,'I''m all right. It feels like we''ve been apart for a lifetime. And it might have been... If the Chancellor hadn''t been kidnapped. I don''t think they would have ever brought us back from the Outer Rim sieges.'),(6,6,2,'Wait, not here...'),(6,2,6,'Yes, here! I''m tired of all this deception. I don''t care if they know we''re married.'),(6,6,2,'Anakin, don''t say things like that.'),(6,2,6,'Are you all right? You''re trembling. What''s going on?'),(6,6,2,'Something wonderful has happened. Ani, I''m pregnant.'),(6,2,6,'That''s... Well that''s wonderful'),(6,6,2,'What are we gonna do?'),(6,2,6,'We''re not going to worry about anything right now, all right? This is a happy moment. The happiest moment of my life.'),(6,9,1,'Yes, Lord Sidious.'),(6,1,9,'General Grievous... I suggest you move the separatist leaders to Mustafar.'),(6,9,1,'It will be done, My Lord.'),(6,1,9,'The end of the war is near, General.'),(6,9,1,'But the loss of Count Dooku?'),(6,1,9,'His death was a necessary loss. Soon I will have a new apprentice- one far younger and more powerful.'),(6,6,2,'Ani, I want to have our baby back home on Naboo. We can go to the lake country where no one will know... where we can be safe. I can go early and fix up the baby''s room. I know the perfect spot, right by the gardens.'),(6,2,6,'You are so beautiful!'),(6,6,2,'It''s only because I''m so in love...'),(6,2,6,'No, no, it''s because I''m so in love with you.'),(6,6,2,'So love has blinded you?'),(6,2,6,'Well, that''s not exactly what I meant...'),(6,6,2,'But it''s probably true! Anakin, help me! What''s bothering you?'),(6,2,6,'Nothing... I remember when I gave this to you.'),(6,6,2,'How long is it going to take for us to be honest with each other?'),(6,2,6,'It was a dream.'),(6,6,2,'Bad?'),(6,2,6,'Like the ones I used to have about my mother just before she died.'),(6,6,2,'And?'),(6,2,6,'And it was about you.'),(6,6,2,'Tell me.'),(6,2,6,'It was only a dream. You die in childbirth...'),(6,6,2,'And the baby?'),(6,2,6,'I don''t know.'),(6,6,2,'It was only a dream.'),(6,2,6,'...I won''t let this one become real.'),(6,6,2,'This baby will change our lives. I doubt the Queen will continue to allow me to serve in the Senate, and if the Council discovers you are the father, you will be expelled-.'),(6,2,6,'I know, I know.'),(6,6,2,'Do you think Obi-Wan might be able to help us?'),(6,2,6,'We don''t need his help. Our baby is a blessing.'),(6,7,2,'Premonitions... premonitions... Hm... these visions you have...'),(6,2,7,'They are of pain, suffering, death...'),(6,7,2,'Yourself you speak of, or someone you know?'),(6,2,7,'Someone...'),(6,7,2,'...close to you?'),(6,2,7,'Yes.'),(6,7,2,'Careful you must be when sensing the future, Anakin. The fear of loss is a path to the dark side.'),(6,2,7,'I won''t let these visions come true, Master Yoda.'),(6,7,2,'Death is a natural part of life. Rejoice for those around you who transform into the Force. Mourn them, do not. Miss them, do not. Attachment leads to jealousy. The shadow of greed, that is.'),(6,2,7,'What must I do, Master Yoda?'),(6,7,2,'Train yourself to let go of everything you fear to lose.'),(6,3,2,'You missed the report on the Outer Rim sieges.'),(6,2,3,'I''m sorry, I was held up. I have no excuse.'),(6,3,2,'In short, they are going very well. Saleucami has fallen, and Master Vos has moved his troops to Boz Pity.'),(6,2,3,'What''s wrong then?'),(6,3,2,'The Senate is expected to vote more executive powers to the Chancellor today.'),(6,2,3,'Well, that can only mean less deliberating and more action. Is that bad? It will make it easier for us to end this war.'),(6,3,2,'Be careful of your friend Palpatine.'),(6,2,3,'Be careful of what?'),(6,3,2,'He has requested your presence.'),(6,2,3,'What for?'),(6,3,2,'He would not say.'),(6,2,3,'He didn''t inform the Council? That''s unusual, isn''t it?'),(6,3,2,'All of this is unusual, and it''s making me feel uneasy.'),(6,1,2,'I hope you trust me, Anakin.'),(6,2,1,'Of course.'),(6,1,2,'I need your help, son.'),(6,2,1,'What do you mean?'),(6,1,2,'I''m depending on you.'),(6,2,1,'For what? I don''t understand.'),(6,1,2,'To be the eyes, ears and voice of the Republic. Anakin... I''m appointing you to be my personal representative on the Jedi Council.'),(6,2,1,'Me? A Master? I am overwhelmed, sir, but the Council elects its own members. They''ll never accept this.'),(6,1,2,'I think they will... they need you more than you know.'),(6,7,2,'Allow this appointment lightly, the Council does not. Disturbing is this move by Chancellor Palpatine.'),(6,2,7,'I understand.'),(6,8,2,'You are on this Council, but we do not grant you the rank of Master.'),(6,2,8,'What? ! How can you do this?? This is outrageous, it''s unfair... How can you be on the Council and not be a Master?'),(6,8,2,'Take a seat, young Skywalker.'),(6,2,8,'Forgive me, Master.'),(6,3,7,'We do not have many ships to spare.'),(6,8,7,'It is critical we send an attack group there, immediately!'),(6,3,7,'He''s right, that is a system we cannot afford to lose.'),(6,7,8,'Go, I will. Good relations with the Wookiees, I have.'),(6,8,2,'It is settled then. Yoda will take a battalion of clones to reinforce the Wookiees on Kashyyyk. May the Force be with us all.'),(6,2,3,'What kind of nonsense is this, put me on the Council and not make me a Master!?? That''s never been done in the history of the Jedi. It''s insulting!'),(6,3,2,'Calm down, Anakin. You have been given a great honor. To be on the Council at your age... It''s never happened before. The fact of the matter is you''re too close to the Chancellor. The Council doesn''t like it when he interferes in Jedi affairs.'),(6,2,3,'I swear to you, I didn''t ask to be put on the Council...'),(6,3,2,'But it''s what you wanted! Your friendship with Chancellor Palpatine seems to have paid off.'),(6,2,3,'That has nothing to do with this.'),(6,3,2,'The only reason the Council has approved your appointment is because the Chancellor trusts you.'),(6,2,3,'And?'),(6,3,2,'Anakin, I am on your side. I didn''t want to put you in this situation.'),(6,2,3,'What situation?'),(6,3,2,'The Council wants you to report on all of the Chancellor''s dealings. They want to know what he''s up to.'),(6,2,3,'They want me to spy on the Chancellor? That''s treason!'),(6,3,2,'We are at war, Anakin.'),(6,2,3,'Why didn''t the Council give me this assignment when we were in session?'),(6,3,2,'This assignment is not to be on record.'),(6,2,3,'The Chancellor is not a bad man, Obi-Wan. He befriended me. He''s watched out for me ever since I arrived here.'),(6,3,2,'That is why you must help us. Anakin, our allegiance is to the Senate, not to its leader who has managed to stay in office long after his term has expired.'),(6,2,3,'The Senate demanded that he stay longer.'),(6,3,2,'Yes, but use your feelings, Anakin. Something is out of place.'),(6,2,3,'You''re asking me to do something against the Jedi Code. Against the Republic. Against a mentor... and a friend. That''s what''s out of place here. Why are you asking this of me?'),(6,3,2,'The Council is asking you.'),(6,3,7,'Anakin did not take to his assignment with much enthusiasm.'),(6,8,3,'It''s very dangerous, putting them together. I don''t think the boy can handle it. I don''t trust him.'),(6,3,8,'With all due respect, Master, is he not the Chosen One? Is he not to destroy the Sith and bring balance to the Force?'),(6,8,3,'So the prophecy says.'),(6,7,3,'A prophecy... that misread could have been.'),(6,3,7,'He will not let me down. He never has.'),(6,7,3,'I hope right you are.'),(6,2,6,'Sometimes, I wonder what''s happening to the Jedi Order... I think this war is destroying the principles of the Republic.'),(6,6,2,'Have you ever considered that we may be on the wrong side?'),(6,2,6,'What do you mean?'),(6,6,2,'What if the democracy we thought we were serving no longer exists, and the Republic has become the very evil we''ve been fighting to destroy?'),(6,2,6,'I don''t believe that. And you''re sounding like a Separatist!'),(6,6,2,'This war represents a failure to listen... Now, you''re closer to the Chancellor than anyone. Please, ask him to stop the fighting and let diplomacy resume.'),(6,2,6,'Don''t ask me to do that. Make a motion in the Senate, where that kind of a request belongs.'),(6,6,2,'What is it?'),(6,2,6,'Nothing.'),(6,6,2,'Don''t do this... don''t shut me out. Let me help you. Hold me... like you did by the lake on Naboo, so long ago... when there was nothing but our love... No politics, no plotting... no war.'),(6,2,1,'You wanted to see me, Chancellor.'),(6,1,2,'Yes, Anakin! Come closer. I have good news. Our Clone Intelligence Units have discovered the location of General Grievous. He''s hiding in the Utapau system.'),(6,2,1,'At last, we''ll be able to capture that monster and end this war.'),(6,1,2,'I would worry about the collective wisdom of the Council if they didn''t select you for this assignment. You are the best choice, by far. Sit down,'),(6,1,2,'Anakin, you know I''m not able to rely on the Jedi Council. If they haven''t included you in their plot, they soon will.'),(6,2,1,'I''m not sure I understand.'),(6,1,2,'You must sense what I have come to suspect... the Jedi Council want control of the Republic... they''re planning to betray me.'),(6,2,1,'I don''t think...'),(6,1,2,'Anakin, search your feelings. You know, don''t you?'),(6,2,1,'I know they don''t trust you...'),(6,1,2,'Or the Senate... or the Republic... or democracy for that matter.'),(6,2,1,'I have to admit my trust in them has been shaken.'),(6,1,2,'Why? They asked you to do something that made you feel dishonest, didn''t they? They asked you to spy on me, didn''t they?'),(6,2,1,'I don''t uh... I don''t know what to say.'),(6,1,2,'Remember back to your early teachings. "All who gain power are afraid to lose it." Even the Jedi.'),(6,2,1,'The Jedi use their power for good.'),(6,1,2,'Good is a point of view, Anakin. The Sith and the Jedi are similar in almost every way, including their quest for greater power.'),(6,2,1,'The Sith rely on their passion for their strength. They think inwards, only about themselves.'),(6,1,2,'And the Jedi don''t?'),(6,2,1,'The Jedi are selfless... they only care about others.'),(6,1,2,'Did you ever hear the tragedy of Darth Plagueis the wise?'),(6,2,1,'No.'),(6,1,2,'I thought not. It''s not a story the Jedi would tell you. It''s a Sith legend. Darth Plagueis was a Dark Lord of the Sith, so powerful and so wise he could use the Force to influence the midi-chlorians to create life... He had such a knowledge of the dark side that he could even keep the ones he cared about from dying.'),(6,2,1,'He could actually save people from death?'),(6,1,2,'The dark side of the Force is a pathway to many abilities some consider to be unnatural.'),(6,2,1,'What happened to him?'),(6,1,2,'He became so powerful... the only thing he was afraid of was losing his power, which eventually, of course, he did. Unfortunately, he taught his apprentice everything he knew, then his apprentice killed him in his sleep. It''s ironic he could save others from death, but not himself.'),(6,2,1,'Is it possible to learn this power?'),(6,1,2,'Not from a Jedi.'),(6,2,3,'A partial message was intercepted in a diplomatic packet from the Chairman of Utapau.'),(6,7,2,'Act on this, we must. The capture of General Grievous will end this war. Quickly and decisively we should proceed.'),(6,2,3,'The Chancellor has requested that I lead the campaign.'),(6,8,2,'The Council will make up its own mind who is to go, not the Chancellor.'),(6,7,2,'A Master is needed, with more experience.'),(6,7,2,'I agree.'),(6,8,2,'Aye Very well. Council is adjourned.'),(6,2,3,'You''re going to need me on this one, Master.'),(6,3,2,'Oh, I agree. However it may turn out just to be a wild bantha chase.'),(6,2,3,'Master! I''ve disappointed you. I have not been very appreciative of your training... I have been arrogant and I apologize... I''ve just been so frustrated with the Council.'),(6,3,2,'You are strong and wise, Anakin, and I am very proud of you. I have trained you since you were a small boy. I have taught you everything I know. And you have become a far greater Jedi than I could ever hope to be. But be patient, Anakin. It won''t be long before the Council makes you a Jedi Master.'),(6,2,3,'Obi-Wan. May the Force be with you.'),(6,3,2,'Good-bye, old friend. May the Force be with you.'),(6,2,6,'Obi-Wan''s been here, hasn''t he?'),(6,6,2,'He came by this morning.'),(6,2,6,'What did he want?'),(6,6,2,'He''s worried about you. He says you''re been under a lot of stress.'),(6,2,6,'I feel lost.'),(6,6,2,'Lost? What do you mean?'),(6,2,6,'Obi-Wan and the Council don''t trust me.'),(6,6,2,'They trust you with their lives.'),(6,2,6,'Something''s happening... I''m not the Jedi I should be. I want more, and I know I shouldn''t.'),(6,6,2,'You expect too much of yourself.'),(6,2,6,'I have found a way to save you.'),(6,6,2,'Save me?'),(6,2,6,'From my nightmares.'),(6,6,2,'Is that what''s bothering you?'),(6,2,6,'I won''t lose you, Padme.'),(6,6,2,'I''m not going to die in childbirth, Annie. I promise you.'),(6,2,6,'No, I promise you!'),(6,3,9,'Hello, there!'),(6,9,3,'General Kenobi, you are a bold one.'),(6,3,9,'Your move.'),(6,9,3,'You fool. I have been trained in your Jedi arts by Count Dooku. Attack, Kenobi. Army or not, you must realize you are doomed.'),(6,3,9,'Oh, I don''t think so.'),(6,8,2,'Anakin, deliver this report to the chancellor. His reaction will give us a clue to his intentions.'),(6,2,8,'Yes, Master.'),(6,8,7,'I sense a plot to destroy the Jedi. The dark side of the Force surrounds the Chancellor.'),(6,8,7,'The jedi council would have to take control of the senate in order to secure a peaceful transition.'),(6,7,8,'To a dark place this line of thought will carry us. Hmm... great care we must take.'),(6,2,1,'Chancellor, we have just received a report from Master Kenobi. He has engaged General Grievous.'),(6,1,2,'We can only hope that Master Kenobi is up to the challenge.'),(6,2,1,'I should be there with him.'),(6,1,2,'It is upsetting to me to see that the Council doesn''t seem to fully appreciate your talents. Don''t you wonder why they won''t make you a Jedi Master?'),(6,2,1,'I wish I knew. More and more I get the feeling that I am being excluded from the Council. I know there are things about the Force that they are not telling me.'),(6,1,2,'They don''t trust you, Anakin. They see your future. They know your power will be too strong to control. You must break through the fog of lies the Jedi have created around you. Let me help you to know the subtleties of the Force.'),(6,2,1,'How do you know the ways of the Force?'),(6,1,2,'My mentor taught me everything about the Force... even the nature of the dark side.'),(6,2,1,'You know the dark side?'),(6,1,2,'Anakin, if one is to understand the great mystery, one must study all its aspects, not just the dogmatic, narrow view of the Jedi. If you wish to become a complete and wise leader, you must embrace a larger view of the Force. Be careful of the Jedi, Anakin. Only through me can you achieve a power greater than any Jedi. Learn to know the dark side of the Force and you will be able to save your wife from certain death.'),(6,2,1,'What did you say?'),(6,1,2,'Use my knowledge, I beg you...'),(6,2,1,'You''re the Sith Lord!'),(6,1,2,'I know what has been troubling you... Listen to me. Don''t continue to be a pawn of the Jedi Council! Ever since I''ve known you, you''ve been searching for a life greater than that of an ordinary Jedi... a life of significance, of conscience. Are you going to kill me?'),(6,2,1,'I would certainly like to.'),(6,1,2,'I know you would. I can feel your anger. It gives you focus, makes you stronger.'),(6,2,1,'I am going to turn you over to the Jedi Council.'),(6,1,2,'Of course you should. But you''re not sure of their intentions, are you?'),(6,2,1,'I will quickly discover the truth of all this.'),(6,1,2,'You have great wisdom, Anakin. Know the power of the dark side. The power to save Padme.'),(6,3,3,'So uncivilized...'),(6,2,8,'Master Windu, I must talk to you.'),(6,8,2,'Skywalker, we just received word that Obi-Wan has destroyed General Grievous. We''re on our way to make sure the chancellor returns emergency power back to the senate.'),(6,2,8,'He won''t give up his power. I''ve just learned a terrible truth. I think Chancellor Palpatine is a Sith Lord.'),(6,8,2,'A Sith Lord?'),(6,2,8,'Yes. The one we have been looking for.'),(6,8,2,'How do you know this?'),(6,2,8,'He knows the ways of the Force. He has been trained to use the dark side.'),(6,8,2,'Are you sure?'),(6,2,8,'Absolutely.'),(6,8,2,'Then our worst fears have been realized. We must move quickly if the Jedi Order is to survive.'),(6,2,8,'Master, the Chancellor is very powerful. You will need my help if you are going to arrest him.'),(6,8,2,'For your own good, stay out of this affair. I sense a great deal of confusion in you, young Skywalker. There is much fear that clouds your judgment.'),(6,2,8,'I must go, Master.'),(6,8,2,'No. If what you''ve told me is true, you will have gained my trust. But for now, remain here. Wait in the council''s chambers until we''ve returned.'),(6,2,8,'Yes, Master.'),(6,1,8,'Master Windu. I take it General Grievous has been destroyed then. I must say, you''re here sooner than expected.'),(6,8,1,'In the name of the Galactic Senate of the Republic, you are under arrest, Chancellor.'),(6,1,8,'Are you threatening me, Master Jedi?'),(6,8,1,'The Senate will decide your fate.'),(6,1,8,'I am the Senate!'),(6,8,1,'Not yet!'),(6,1,8,'It''s treason, then.'),(6,8,1,'You are under arrest, My Lord.'),(6,1,2,'Anakin! I told you it would come to this. I was right. The Jedi are taking over.'),(6,8,1,'The oppression of the Sith will never return. You have lost.'),(6,1,8,'No! No! No! You will die!'),(6,1,2,'He''s a traitor.'),(6,8,2,'He is a traitor!'),(6,1,2,'I have the power to save the one you love. You must choose.'),(6,8,2,'Don''t listen to him, Anakin!'),(6,1,2,'Don''t let him kill me. I can''t hold it any longer. I can''t. I''m weak. I''m too weak. Anakin! Help me. Help me! I can''t hold on any longer.'),(6,8,1,'I am going to end this once and for all.'),(6,2,8,'You can''t. He must stand trial.'),(6,8,2,'He has control of the senate and the courts. He''s too dangerous to be left alive.'),(6,1,8,'But I''m too weak. Don''t kill me. Please.'),(6,2,8,'It is not the Jedi way... He must live...'),(6,1,8,'Please don''t, please don''t...'),(6,2,8,'I need him...'),(6,1,8,'Please don''t...'),(6,2,8,'NO!'),(6,1,1,'Power! Unlimited power!'),(6,2,2,'What have I done?'),(6,1,2,'You are fulfilling your destiny, Anakin. Become my apprentice. Learn to use the dark side of the Force.'),(6,2,1,'I will do whatever you ask.'),(6,1,2,'Good.'),(6,2,1,'Just help me save Padme''s life. I can''t live without her.'),(6,1,2,'To cheat death is a power only one has achieved, but if we work together, I know we can discover the secret.'),(6,2,1,'I pledge myself to your teachings.'),(6,1,2,'Good. Good. The Force is strong with you. A powerful Sith you will become. Henceforth, you shall be known as Darth... Vader.'),(6,2,1,'Thank you. my Master.'),(6,1,2,'Rise. Because the Council did not trust you, my young apprentice, I believe you are the only Jedi with no knowledge of this plot. When the Jedi learn what has transpired here, they will kill us, along with all the Senators.'),(6,2,1,'I agree. The council''s next move will be against the Senate.'),(6,1,2,'Every single Jedi, including your friend Obi-Wan Kenobi, is now an enemy of the Republic.'),(6,2,1,'I understand, Master.'),(6,1,2,'We must move quickly. The Jedi are relentless; if they are not all destroyed, it will be civil war without end. First, I want you to go to the Jedi Temple. We will catch them off balance. Do what must be done, Lord Vader. Do not hesitate. Show no mercy. Only then will you be strong enough with the dark side to save Padme.'),(6,2,1,'What about the other Jedi spread across the galaxy?'),(6,1,2,'Their betrayal will be dealt with. After you have killed all the Jedi in the Temple, go to the Mustafar system. Wipe out Viceroy Gunray and the other Separatist leaders. Once more, the Sith will rule the galaxy, and we shall have peace.'),(6,6,2,'Are you all right? I heard there was an attack on the Jedi Temple... you can see the smoke from here.'),(6,2,6,'I''m fine. I''m fine. I came to see if you and the baby are safe.'),(6,6,2,'What''s happening?'),(6,2,6,'The Jedi have tried to overthrow the Republic...'),(6,6,2,'I can''t believe that!'),(6,2,6,'I saw Master Windu attempt to assassinate the Chancellor myself.'),(6,6,2,'Oh Anakin, what are you going to do?'),(6,2,6,'I will not betray the Republic... my loyalties lie with the Chancellor and with the Senate... and with you.'),(6,6,2,'What about Obi-Wan?'),(6,2,6,'I don''t know... Many Jedi have been killed. We can only hope that he''s remained loyal to the Chancellor.'),(6,6,2,'Anakin, I''m afraid.'),(6,2,6,'Have faith, my love. Everything will soon be set right. The Chancellor has given me a very important mission. The Separatists have gathered on the Mustafar system. I''m going there to end this war. Wait for me until I return. Things will be different, I promise. Please, wait for me.'),(6,3,7,'How many other Jedi managed to survive?'),(6,7,3,'Heard from no one, have we.'),(6,3,7,'Have we had any contact from the Temple?'),(6,7,3,'Received a coded retreat message, we have.'),(6,3,7,'Well, then we must go back! If there are other stragglers, they will fall into the trap and be killed.'),(6,7,3,'Suggest dismantling the coded signal, do you?'),(6,3,7,'Yes, Master. There is too much at stake'),(6,7,3,'I agree. And a little more knowledge might light our way.'),(6,7,3,'If a special session of Congress there is, easier for us to enter the Jedi Temple it will be.'),(6,3,7,'Not even the younglings survived.'),(6,7,3,'Killed not by clones, this Padawan. By a lightsaber, he was.'),(6,3,7,'Who? Who could have done this?'),(6,3,7,'I''ve recalibrated the code warning all surviving Jedi to stay away.'),(6,7,3,'For the Clones to discover the recalibration, a long time it will take.'),(6,3,7,'Wait, Master. There is something I must know...'),(6,7,3,'If into the security recordings you go, only pain will you find.'),(6,3,7,'I must know the truth, Master. It can''t be... It can''t be...'),(6,1,2,'You have done well, my new apprentice. Now, Lord Vader, go and bring peace to the Empire.'),(6,3,7,'I can''t watch anymore'),(6,7,3,'Destroy the Sith, we must.'),(6,3,7,'Send me to kill the Emperor. I will not kill Anakin.'),(6,7,3,'To fight this Lord Sidious, strong enough, you are not.'),(6,3,7,'He is like my brother... I cannot do it.'),(6,7,3,'Twisted by the dark side, young Skywalker has become. The boy you trained, gone he is... Consumed by Darth Vader.'),(6,3,7,'I do not know where the Emperor has sent him. I don''t know where to look.'),(6,7,3,'Use your feelings, Obi-Wan, and find him, you will.'),(6,3,6,'When was the last time you saw him?'),(6,6,3,'Yesterday.'),(6,3,6,'And do you know where he is now?'),(6,6,3,'No.'),(6,3,6,'Padme, I need your help. He''s in grave danger.'),(6,6,3,'From the Sith?'),(6,3,6,'From himself... Padme, Anakin has turned to the dark side.'),(6,6,3,'You''re wrong! How could you even say that?'),(6,3,6,'I have seen a security hologram of him killing younglings.'),(6,6,3,'Not Anakin! He couldn''t!'),(6,3,6,'He was deceived by a lie. We all were. It appears that the Chancellor is behind everything, including the war. Palpatine is the Sith Lord we''ve been looking for. After the death of Count Dooku, Anakin became his new apprentice.'),(6,6,3,'I don''t believe you... I can''t.'),(6,3,6,'Padme, I must find him.'),(6,6,3,'You''re going to kill him, aren''t you?'),(6,3,6,'He has become a very great threat.'),(6,6,3,'I can''t...'),(6,3,6,'Anakin is the father, isn''t he? I''m so sorry.'),(6,6,6,'This is something I must do myself. Besides, Threepio will look after me.'),(6,2,1,'The Separatists have been taken care of, My Master.'),(6,1,2,'It is finished then. You have restored peace and justice to the galaxy. Send a message to the ships of the Trade Federation. All droid units must shut down immediately.'),(6,2,1,'Very good, My Lord.'),(6,2,6,'I saw your ship... What are you doing out here?'),(6,6,2,'I was so worried about you. Obi-Wan told me terrible things.'),(6,2,6,'What things?'),(6,6,2,'He said you have turned to the dark side... that you killed younglings.'),(6,2,6,'Obi-Wan is trying to turn you against me.'),(6,6,2,'He cares about us.'),(6,2,6,'Us?'),(6,6,2,'He knows... He wants to help you. Anakin, all I want is your love.'),(6,2,6,'Love won''t save you, Padme. Only my new powers can do that.'),(6,6,2,'At what cost? You are a good person. Don''t do this.'),(6,2,6,'I won''t lose you the way I lost my mother! I am becoming more powerful than any Jedi has ever dreamed of and I''m doing it for you. To protect you.'),(6,6,2,'Come away with me. Help me raise our child. Leave everything else behind while we still can.'),(6,2,6,'Don''t you see, we don''t have to run away anymore. I have brought peace to the Republic. I am more powerful than the Chancellor. I can overthrow him, and together you and I can rule the galaxy. Make things the way we want them to be.'),(6,6,2,'I don''t believe what I''m hearing... Obi-Wan was right. You''ve changed.'),(6,2,6,'I don''t want to hear any more about Obi-Wan. The Jedi turned against me. Don''t you turn against me.'),(6,6,2,'I don''t know you anymore. Anakin, you''re breaking my heart. You''re going down a path I can''t follow.'),(6,2,6,'Because of Obi-Wan?'),(6,6,2,'Because of what you''ve done... what you plan to do. Stop, stop now. Come back! I love you.'),(6,2,6,'Liar!'),(6,6,2,'No!'),(6,2,6,'You''re with him. You brought him here to kill me!'),(6,3,2,'Let her go, Anakin!'),(6,6,2,'No! Anakin.'),(6,3,2,'Let her go.'),(6,2,3,'You turned her against me.'),(6,3,2,'You have done that yourself.'),(6,2,3,'You will not take her from me.'),(6,3,2,'Your anger and your lust for power have already done that. You have allowed this Dark Lord to twist your mind until now... until now you have become the very thing you swore to destroy.'),(6,2,3,'Don''t lecture me, Obi-Wan. I see through the lies of the Jedi. I do not fear the dark side as you do. I have brought peace, freedom, justice, and security to my new Empire.'),(6,3,2,'Your new Empire?'),(6,2,3,'Don''t make me kill you.'),(6,3,2,'Anakin, my allegiance is to the Republic... to democracy.'),(6,2,3,'If you''re not with me, then you''re my enemy.'),(6,3,2,'Only a Sith deals in absolutes. I will do what I must.'),(6,2,3,'You will try.'),(6,7,1,'I hear a new apprentice, you have. Emperor, or should I call you Darth Sidious?'),(6,1,7,'Master Yoda. You survived.'),(6,7,1,'Surprised?'),(6,1,7,'Your arrogance blinds you, Master Yoda. Now you will experience the full power of the dark side. I have waited a long time for this moment, my little green friend. At last the Jedi are no more.'),(6,7,1,'Not if anything to say about it, I have. At an end your rule is and not short enough it was. If so powerful you are, why leave?'),(6,1,7,'You will not stop me. Darth Vader will become more powerful than either of us.'),(6,7,1,'Faith in your new apprentice, misplaced may be, as is your faith in the dark side of the Force.'),(6,3,2,'I have failed you, Anakin. I have failed you.'),(6,2,3,'I should have known the Jedi were plotting to take over.'),(6,3,2,'Anakin, Chancellor Palpatine is evil.'),(6,2,3,'From my point of view, the Jedi are evil.'),(6,3,2,'Well, then you are lost!'),(6,2,3,'This is the end for you, My Master.'),(6,3,2,'It''s over, Anakin. I have the high ground.'),(6,2,3,'You underestimate my power!'),(6,3,2,'Don''t try it. You were the Chosen One! It was said that you would, destroy the Sith, not join them. Bring balance to the Force, not leave it in darkness.'),(6,2,3,'I hate you!'),(6,3,2,'You were my brother, Anakin. I loved you.'),(6,6,3,'Obi-Wan. Is Anakin all right?'),(6,6,3,'Luke.'),(6,3,6,'It''s a girl.'),(6,6,3,'...Leia. Obi-Wan? There''s good in him. I know. I know there''s...still...'),(6,1,2,'Lord Vader, can you hear me?'),(6,2,1,'Yes, Master. Where is Padme? Is she safe, is she all right?'),(6,1,2,'It seems, in your anger, you killed her.'),(6,2,1,'I? I couldn''t have. She was alive! I felt it! No!'),(6,7,3,'Hidden, safe, the children must be kept.'),(6,3,7,'We must take them somewhere the Sith will not sense their presence.'),(6,7,3,'Split up, they should be.'),(6,3,7,'And what of the boy?'),(6,7,3,'To Tatooine. To his family, send him.'),(6,3,7,'I will take the child and watch over him.'),(6,7,3,'Until the time is right, disappear we will.'),(6,7,3,'Master Kenobi, wait a moment. In your solitude on Tatooine, training I have for you.'),(6,3,7,'Training?'),(6,7,3,'An old friend has learned the path to immortality.'),(6,3,7,'Who?'),(6,7,3,'One who has returned from the netherworld of the Force to train me... your old Master.'),(6,3,7,'Qui-Gon?'),(6,7,3,'How to commune with him. I will teach you.')
GO

EXEC GenerateCharactersMoviesRelations
EXEC GenerateWordsSpokenPerLine
EXEC GenerateDialogueStats
EXEC GenerateWordsSpokenPerMovie

-- ---------------------------------
-- Views - creating
-- ---------------------------------
IF OBJECT_ID('ViewMasterOfBabblerPerMovie', 'V') IS NOT NULL
    DROP VIEW ViewMasterOfBabblerPerMovie
GO

CREATE VIEW ViewMasterOfBabblerPerMovie AS
  WITH Inter_CTE  AS
           (
               SELECT
                   cmr1.CharacterID,
                   cmr2.MaxWords,
                   cmr2.MovieID,
                   mar.MasterID
                 FROM CharactersMoviesRelations cmr1
                          INNER JOIN (SELECT MovieID, MaxWords=MAX(NumWordsSpoken) FROM CharactersMoviesRelations GROUP BY MovieID) cmr2
                                     ON cmr1.MovieID=cmr2.MovieID AND cmr1.NumWordsSpoken=cmr2.MaxWords
                          LEFT JOIN MasterApprenticeRelations mar ON cmr1.CharacterID = mar.ApprenticeID
           )
      (
          SELECT
              [Movie Part]=i.MovieID,
              [Movie Name]=(SELECT Name FROM Movies WHERE PartID=i.MovieID),
              [Character With Most Words]=(SELECT Name FROM Characters WHERE ID=i.CharacterID),
              [Words]=(SELECT TOP 1 i3.MaxWords FROM Inter_CTE AS i3 WHERE i3.CharacterID=i.CharacterID AND i3.MovieID=i.MovieID),
              [This Character's Master(s)]=STUFF(
                      (
                          SELECT ', ' + (SELECT Name FROM Characters WHERE ID=i2.MasterID)
                            FROM Inter_CTE AS i2
                           WHERE i2.CharacterID=i.CharacterID AND i2.MovieID=i.MovieID
                             FOR xml PATH('')
                      ),
                      1, 1, '')

            FROM Inter_CTE AS i
                     INNER JOIN MasterApprenticeRelations mar ON i.CharacterID=mar.ApprenticeID AND mar.MasterID=i.MasterID
                     INNER JOIN Characters C ON i.CharacterID=C.ID
           GROUP BY MovieID, CharacterID
      )
GO


IF OBJECT_ID('ViewPlanetWithCharactersWithMostMidichlorians', 'V') IS NOT NULL
    DROP VIEW ViewPlanetWithCharactersWithMostMidichlorians
GO

CREATE VIEW ViewPlanetWithCharactersWithMostMidichlorians AS
(
SELECT TOP 1
    Planet=(SELECT Name FROM Planets WHERE ID=P.ID),
    [Maximum # of midichlorians]=AVG(C.Midichlorians),
    [Characters Count]=COUNT(C.ID),
    [Top Representative]=(SELECT TOP 1 Name FROM Characters ORDER BY Midichlorians DESC)

FROM Characters C
         INNER JOIN Planets P ON P.ID = C.FromPlanet
GROUP BY P.ID
ORDER BY [Maximum # of midichlorians] DESC
)
GO


IF OBJECT_ID('ViewMostMoneyEarnedByTalking', 'V') IS NOT NULL
    DROP VIEW ViewMostMoneyEarnedByTalking
GO
CREATE VIEW ViewMostMoneyEarnedByTalking AS (
SELECT
     C.Name,
     max.MaxWorthWord
   FROM Characters C
            JOIN (
       SELECT
           CharacterID=C.ID,
           MaxWorthWord=AVG(1.0 * ISNULL(CMR.NumWordsSpoken, 0) / M.WordsSpoken * M.BoxOffice)
         FROM Movies m
           CROSS JOIN Characters C
           LEFT JOIN CharactersMoviesRelations CMR ON C.ID=CMR.CharacterID AND MovieID=m.PartID
         GROUP BY C.ID
   ) max
ON max.CharacterID=C.ID
)
GO

IF OBJECT_ID('MostOrLeastExpensiveWordPerMovie', 'P') IS NOT NULL
    DROP PROCEDURE MostOrLeastExpensiveWordPerMovie
GO

CREATE PROCEDURE MostOrLeastExpensiveWordPerMovie @arg varchar(30) AS BEGIN
WITH CTE AS
(
SELECT
       *,
	 Worth=1.0 * CMR.NumWordsSpoken / M.WordsSpoken * M.BoxOffice / 1000000,
     rn = row_number() OVER(PARTITION BY CMR.MovieID ORDER BY
	 CASE @arg WHEN 'MOST' THEN 1.0 * CMR.NumWordsSpoken / M.WordsSpoken END DESC,
	 CASE @arg WHEN 'LEAST' THEN 1.0 * CMR.NumWordsSpoken / M.WordsSpoken END)
     FROM CharactersMoviesRelations CMR
	 LEFT JOIN Movies M ON M.PartID=CMR.MovieID
)
(
SELECT Character=C.Name, Movie=M.Name, [Worth in millions $]=CTE.Worth FROM CTE
JOIN Characters C ON C.ID=CharacterID
JOIN Movies M ON M.PartID=MovieID
WHERE rn=1
)
END
GO

IF OBJECT_ID('ViewMostTalkativePairs', 'V') IS NOT NULL
    DROP VIEW ViewMostTalkativePairs
GO

CREATE VIEW ViewMostTalkativePairs AS
    WITH CTE AS (
        SELECT ID, NW=SUM(NumWords) FROM ( SELECT
                       CASE WHEN FromID > ToID THEN CONCAT(FromID,ToID)
                 WHEN FromID <= ToID THEN CONCAT(ToID,FromID)
END AS ID,
               *
          FROM DialogueStats
        ) x GROUP BY ID
    )
    (
SELECT
    Character1=C1.Name,
       Character2=C2.Name,
    [Number of words]=NW,
        [Example longest line]=(
        SELECT TOP 1 Dialogue
          FROM Dialogue D
         WHERE C1.ID = FromID AND C2.ID=ToID OR C2.ID = FromID AND C1.ID=ToID
         ORDER BY WordCount DESC
)
   FROM CTE
        JOIN Characters C1 ON C1.ID=CAST(LEFT(CTE.ID, 1) AS INT)
        JOIN Characters C2 ON C2.ID=CAST(RIGHT(CTE.ID, 1) AS INT)
)
GO

IF OBJECT_ID('ViewLikingSandVSHatingSandFights', 'V') IS NOT NULL
    DROP VIEW ViewLikingSandVSHatingSandFights
GO
CREATE VIEW ViewLikingSandVSHatingSandFights AS
(
    SELECT LikesSand, Wins=Count(F.FirstFighterID)  FROM Characters C
    INNER JOIN Fights F
        ON C.ID = F.FirstFighterID
               AND F.Winner IS NOT NULL
               AND C.LikesSand != (SELECT LikesSand FROM Characters WHERE ID=F.SecondFighterID)
    GROUP BY LikesSand
)
GO
IF OBJECT_ID('ViewJediVsSithFights', 'V') IS NOT NULL
    DROP VIEW ViewJediVsSithFights
GO
CREATE VIEW ViewJediVsSithFights AS (
    SELECT Jedi, Wins=Count(F.FirstFighterID)  FROM Characters C
    INNER JOIN Fights F
        ON C.ID = F.FirstFighterID
               AND F.Winner IS NOT NULL
               AND C.Jedi != (SELECT Jedi FROM Characters WHERE ID=F.SecondFighterID)
    WHERE Jedi IS NOT NULL
    GROUP BY Jedi
    )
GO

IF OBJECT_ID('MostMidichlorians', 'P') IS NOT NULL
    DROP PROCEDURE MostMidichlorians
GO
CREATE PROCEDURE MostMidichlorians @movie TINYINT, @n INT AS BEGIN
    WITH CTE AS (
        SELECT *, ROW=ROW_NUMBER() OVER (ORDER BY Midichlorians DESC) FROM Characters
        INNER JOIN CharactersMoviesRelations CMR ON Characters.ID = CMR.CharacterID
        WHERE CMR.MovieID=@movie
    )(
        SELECT * FROM CTE WHERE ROW = @n
    )
    END
GO
-- ---------------------------------------------
-- Reports - creating
-- ---------------------------------------------


-- REPORT 1
-- View Master (or multiple separated by commas)
-- of the character who spoke the most per each movie.
-- We see that the masters who encouraged talking the most were:
-- - Dooku for Qui-Gon
-- - Qui-Gon taught talking to Obi-Wan, they both taught Anakin alongside Palpatine
SELECT *
FROM ViewMasterOfBabblerPerMovie

-- REPORT 2
-- Planet with highest amount of midichlorians.
-- We see to have the highest chance of being a Force user
-- with large amount of midichlorians we should be born on Tatooine.
SELECT *
FROM ViewPlanetWithCharactersWithMostMidichlorians

-- REPORT 3
-- The amount of box office money in relation to
-- percentage words spoken in all the movies combined.
-- We see that Anakin talking has influence on the movie making a lot of money.
SELECT Name, [Money earned by talking in millions $]=MaxWorthWord/1000000
FROM ViewMostMoneyEarnedByTalking
ORDER BY MaxWorthWord DESC

-- REPORT 4
-- Similar to the above, but we see who talked the most each movie,
-- and also what relation that had on the movie's box office.
EXEC MostOrLeastExpensiveWordPerMovie @arg = 'MOST';

-- REPORT 5
-- Same as above, but we see who talked the least each movie,
-- and also what relation that had on the movie's box office.
EXEC MostOrLeastExpensiveWordPerMovie @arg = 'LEAST';

-- REPORT 6
-- View characters who spoke the most with each other
-- from the set of the Characters table.
SELECT * FROM ViewMostTalkativePairs
ORDER BY [Number of words] DESC

-- REPORT 7
-- Grouping characters in two groups: those who like
-- sand and those who don’t, what was the score of wins/losses
-- when characters from opposing groups fought?
-- 3:2 for liking sand
SELECT * FROM ViewLikingSandVSHatingSandFights

-- REPORT 8
-- Grouping characters in two groups: Jedi and Sith -||-
-- 5:2 for the Sith
SELECT * FROM ViewJediVsSithFights

-- REPORT 9
-- PROCEDURE: Given a movie ID and N (INT), find the character
-- with the nth most # of midichlorians in that movie (NULL if no force-sensitive users in particular movie)
EXEC MostMidichlorians @movie=4, @n=2;


-- ---------------------------------------------
-- Database - deleting
-- Comment this script part, if you run the script on the faculty MSSQL server.
-- ---------------------------------------------
--USE master
--GO

-- IF DB_ID('PrequelsDatabase') IS NOT NULL
-- DROP DATABASE PrequelsDatabase
-- GO
