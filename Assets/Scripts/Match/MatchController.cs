using System.Collections;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using TMPro;

public class MatchController : MonoBehaviour
{
  private const int slotAmmount = 5;

  private float startTime;
  static public TextMeshProUGUI matchTextBox;
  static public TextMeshProUGUI timerTextBox;
  static public TextMeshProUGUI scoreTextBox;



  private int timeLeft;

  public int timerLength = 8;


    public GameObject defPanel;
    public GameObject midPanel;
    public GameObject atkPanel;

    public GameObject footBallPlayerCard;
    public GameObject emptyFootBallPlayerCard;

    void Start(){
    startTime = Time.time;

    timerTextBox = GameObject.FindWithTag("Timer").GetComponent<TextMeshProUGUI>();
    matchTextBox = GameObject.FindWithTag("MatchText").GetComponent<TextMeshProUGUI>();
    scoreTextBox = GameObject.FindWithTag("Score").GetComponent<TextMeshProUGUI>();

    setPlayersInSlots(GameMaster.myClubDefPlayers(), getChildren(defPanel));
    setPlayersInSlots(GameMaster.myClubMidPlayers(), getChildren(midPanel));
    setPlayersInSlots(GameMaster.myClubAtkPlayers(), getChildren(atkPanel));


    }

  void Update(){
    timeLeft = timerLength - (int)(Time.time - startTime);
    if(timeLeft == -1){
      startTime = Time.time;
      GameMaster.nextMatchEvent();
    }
    timerTextBox.text = timeLeft.ToString();

  }



    static public void updateMatchUI(Club currentBallHolder, FootballPlayer currentPlayer, int currentPosition, Club previousBallHolder, FootballPlayer previousPlayer)
    {
        if (same_team(currentBallHolder, previousBallHolder))
        {
            if (same_player(currentPlayer, previousPlayer))
            {
                matchTextBox.text = (currentPlayer.name + " advances to position " +
                                     currentPosition.ToString() + " for " + currentBallHolder.getName());
            }
            else
            {
                matchTextBox.text = (previousPlayer.name + " passes the ball to " +
                                     currentPlayer.name + " at position " + currentPosition.ToString() + " for " +
                                     currentBallHolder.getName());
            }
        }
        else
        {
            matchTextBox.text = (currentPlayer.name + " steals the ball from " + previousPlayer.name + " and advances to position " +
                                 currentPosition.ToString() + " for " + currentBallHolder.getName());
        }
    }

    static public void updateMatchScore(string currentMatchScore, string goaler)
    {
        scoreTextBox.text = currentMatchScore;
        matchTextBox.text = "The club " + goaler + " scored a GOAL!\n The match will resume at 50m.";
    }

    private static bool same_team(Club ballHolder, Club previousBallHolder)
    {
        return previousBallHolder.getName() == ballHolder.getName();
    }

    private static bool same_player(FootballPlayer player, FootballPlayer previousPlayer)
    {
        return previousPlayer.name == player.name;
    }

    // Fucking estructurado horrible.
    private List<GameObject> getChildren(GameObject parent){
    List<GameObject> gameObjects = new List<GameObject>();
    foreach (Transform transform in parent.transform)
    {
        gameObjects.Add(transform.gameObject);
    }
    return gameObjects;
  }

  private void setPlayersInSlots(List<FootballPlayer> footballPlayers, List<GameObject> slots){
    int i = 0;
    foreach(FootballPlayer footballPlayer in footballPlayers){
      var myNewCard = Instantiate(footBallPlayerCard, slots[i].transform, false);
      footBallPlayerCard.GetComponent<FootballPlayerCard>().setPlayerCard(footballPlayers[i]);
      i++;
    }

    while (i <= slotAmmount){
      var myNewCard = Instantiate(emptyFootBallPlayerCard,slots[i].transform , false);
      i++;
    }
  }
}
